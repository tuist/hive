defmodule Hive.Drops do
  @moduledoc """
  Shipped-update entries (GitHub releases + RSS/Atom changelogs).
  Drops are read-only from the dashboard's perspective; their data is
  reconciled by the `Hive.Drops.GitHubReleasesSyncer` and
  `Hive.Drops.RssSyncer`, and routed to domains by
  `Hive.Drops.DomainClassification`.

  A drop has a many-to-many relationship with domains. A drop is
  visible to anonymous viewers when any of its domains is public, and
  to organization members across the board.

  Source management (the RSS/Atom URLs operators register) is
  admin-only and lives behind `Hive.Ops.Policy`. See
  `Hive.Drops.DropSource`.
  """

  import Ecto.Query

  alias Hive.Auth
  alias Hive.Drops.Drop
  alias Hive.Drops.DropDomain
  alias Hive.Drops.DropSource
  alias Hive.Domains.Domain
  alias Hive.Repo

  @default_page_size 20

  @doc "Lists drops the `user` can see, paginated and optionally filtered by domains."
  def list_drops(opts \\ []) do
    user = Keyword.get(opts, :user)
    page = Keyword.get(opts, :page, 1) |> max(1)
    page_size = Keyword.get(opts, :page_size, @default_page_size) |> normalize_page_size()
    domain_ids = Keyword.get(opts, :domain_ids, []) |> normalize_domain_ids()
    query_text = Keyword.get(opts, :query)
    source_type = Keyword.get(opts, :source_type)

    base =
      Drop
      |> apply_visibility(user)
      |> filter_domain_ids(domain_ids)
      |> filter_source_type(source_type)
      |> filter_search(query_text)
      |> distinct(true)

    total_entries = base |> exclude(:order_by) |> Repo.aggregate(:count, :id)
    total_pages = max(1, div(total_entries + page_size - 1, page_size))
    page = min(page, total_pages)

    entries =
      base
      |> order_by([drop], desc: drop.published_at, desc: drop.inserted_at)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(domains: :project, github_repository: [], drop_source: [])
      |> Repo.all()

    {entries,
     %{
       current_page: page,
       page_size: page_size,
       total_entries: total_entries,
       total_pages: total_pages
     }}
  end

  @doc "Lists drops for a single domain ordered by `published_at` descending."
  def list_drops_for_domain(%Domain{} = domain, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Drop
    |> join(:inner, [drop], dm in DropDomain,
      on: dm.drop_id == drop.id and dm.domain_id == ^domain.id
    )
    |> order_by([drop], desc: drop.published_at, desc: drop.inserted_at)
    |> limit(^limit)
    |> preload(domains: :project, github_repository: [], drop_source: [])
    |> Repo.all()
  end

  @doc "Fetches a drop by id when the `user` is allowed to see it."
  def fetch_visible_drop(id, user) when is_binary(id) do
    case Repo.get(Drop, id) do
      nil ->
        {:error, :not_found}

      %Drop{} = drop ->
        drop = Repo.preload(drop, [:domains, :github_repository, :drop_source])

        if visible?(drop, user),
          do: {:ok, drop},
          else: {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc "Idempotently inserts or updates a drop based on the unique (source_type, external_id)."
  def upsert_drop(attrs) when is_map(attrs) do
    %Drop{}
    |> Drop.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:title, :body, :url, :published_at, :updated_at]},
      conflict_target: [:source_type, :external_id],
      returning: true
    )
  end

  @doc """
  Upserts a GitHub-release-sourced drop while preserving the
  agent-rewritten body. New drops store the raw release body in both
  `body` and `raw_body`; existing drops keep `body` (which may be the
  agent's rewrite) intact unless the upstream `raw_body` actually
  changed, in which case `rewritten_at` is cleared so the rewriter
  worker re-runs.
  """
  def upsert_release_drop(attrs) when is_map(attrs) do
    attrs = atomize_keys(attrs)
    raw_body = Map.get(attrs, :body)

    lookup = [source_type: :github_release, external_id: Map.fetch!(attrs, :external_id)]

    case Repo.get_by(Drop, lookup) do
      nil ->
        attrs
        |> Map.merge(%{raw_body: raw_body, body: raw_body, rewritten_at: nil})
        |> then(&Drop.changeset(%Drop{}, &1))
        |> Repo.insert()

      %Drop{} = existing ->
        update_attrs = %{
          title: Map.get(attrs, :title) || existing.title,
          url: Map.get(attrs, :url) || existing.url,
          published_at: Map.get(attrs, :published_at) || existing.published_at,
          github_repository_id:
            Map.get(attrs, :github_repository_id) || existing.github_repository_id
        }

        update_attrs =
          if existing.raw_body == raw_body do
            update_attrs
          else
            Map.merge(update_attrs, %{
              raw_body: raw_body,
              body: raw_body,
              rewritten_at: nil
            })
          end

        existing
        |> Drop.changeset(update_attrs)
        |> Repo.update()
    end
  end

  @doc "Persists the agent-rewritten body and stamps `rewritten_at`."
  def mark_rewritten(%Drop{} = drop, rewritten_body) when is_binary(rewritten_body) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    drop
    |> Drop.changeset(%{body: rewritten_body, rewritten_at: now})
    |> Repo.update()
  end

  def get_drop(id) when is_binary(id) do
    case Repo.get(Drop, id) do
      nil -> nil
      %Drop{} = drop -> Repo.preload(drop, [:domains, :github_repository, :drop_source])
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  @doc """
  Replaces the domain links for `drop` with the given `domain_ids` and
  stamps `classified_at` so the sweeper does not pick the row up again.
  Passes through the list of domain ids that were actually linked.
  """
  def replace_drop_domains(%Drop{} = drop, domain_ids) when is_list(domain_ids) do
    classified_at = DateTime.utc_now() |> DateTime.truncate(:second)

    selected =
      domain_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    inserted_at = classified_at

    rows =
      Enum.map(selected, fn domain_id ->
        %{
          drop_id: drop.id,
          domain_id: domain_id,
          inserted_at: inserted_at,
          updated_at: inserted_at
        }
      end)

    Repo.transaction(fn ->
      from(link in DropDomain, where: link.drop_id == ^drop.id)
      |> Repo.delete_all()

      if rows != [], do: Repo.insert_all(DropDomain, rows)

      Drop
      |> where([drop], drop.id == ^drop.id)
      |> Repo.update_all(set: [classified_at: classified_at])
    end)

    selected
  end

  @doc "Returns drops whose `classified_at` is nil, oldest first. Used by the sweeper."
  def list_unclassified_drops(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Drop
    |> where([drop], is_nil(drop.classified_at))
    |> order_by([drop], asc: drop.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Lists every RSS/Atom drop source registered."
  def list_drop_sources do
    DropSource
    |> order_by([source], asc: source.inserted_at)
    |> Repo.all()
  end

  @doc "Lists drop sources that are eligible to be polled by the RSS syncer."
  def list_pollable_sources do
    DropSource
    |> where([source], source.enabled == true)
    |> Repo.all()
  end

  def get_drop_source!(id), do: Repo.get!(DropSource, id)

  def change_drop_source(source \\ %DropSource{}, attrs \\ %{}),
    do: DropSource.changeset(source, attrs)

  def create_drop_source(attrs) do
    %DropSource{}
    |> DropSource.changeset(attrs)
    |> Repo.insert()
  end

  def update_drop_source(%DropSource{} = source, attrs) do
    source
    |> DropSource.changeset(attrs)
    |> Repo.update()
  end

  def delete_drop_source(%DropSource{} = source), do: Repo.delete(source)

  @doc "Records the outcome of a poll attempt on the given source."
  def record_source_poll(%DropSource{} = source, :ok) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    source
    |> DropSource.poll_changeset(%{
      last_polled_at: now,
      last_error: nil,
      last_error_at: nil
    })
    |> Repo.update()
  end

  def record_source_poll(%DropSource{} = source, {:error, reason}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    source
    |> DropSource.poll_changeset(%{
      last_polled_at: now,
      last_error: format_error(reason),
      last_error_at: now
    })
    |> Repo.update()
  end

  @doc "Returns true when `drop` is visible to `user`."
  def visible?(%Drop{} = drop, user) do
    domains = drop.domains || Repo.preload(drop, :domains).domains

    cond do
      Auth.member?(user) -> true
      Enum.any?(domains, &(&1.visibility == :public)) -> true
      true -> false
    end
  end

  def source_type_label(:github_release), do: "GitHub release"
  def source_type_label(:rss), do: "RSS"
  def source_type_label(value) when is_atom(value), do: value |> Atom.to_string()
  def source_type_label(_value), do: "Drop"

  defp apply_visibility(query, user) do
    if Auth.member?(user) do
      query
      |> join(:left, [drop], dm in DropDomain, on: dm.drop_id == drop.id, as: :domain_link)
    else
      query
      |> join(:inner, [drop], dm in DropDomain, on: dm.drop_id == drop.id, as: :domain_link)
      |> join(:inner, [domain_link: dm], domain in Domain,
        on: domain.id == dm.domain_id and domain.visibility == :public,
        as: :public_domain
      )
    end
  end

  defp filter_domain_ids(query, []), do: query

  defp filter_domain_ids(query, ids) when is_list(ids) do
    where(query, [domain_link: dm], dm.domain_id in ^ids)
  end

  defp filter_source_type(query, nil), do: query

  defp filter_source_type(query, type) when type in [:github_release, :rss] do
    where(query, [drop], drop.source_type == ^type)
  end

  defp filter_source_type(query, _type), do: query

  defp filter_search(query, nil), do: query
  defp filter_search(query, ""), do: query

  defp filter_search(query, text) when is_binary(text) do
    pattern = "%" <> escape_like(text) <> "%"

    where(
      query,
      [drop],
      ilike(drop.title, ^pattern) or ilike(drop.body, ^pattern)
    )
  end

  defp normalize_page_size(size) when is_integer(size) and size > 0 and size <= 100, do: size
  defp normalize_page_size(:all), do: 10_000
  defp normalize_page_size(_size), do: @default_page_size

  defp normalize_domain_ids(nil), do: []
  defp normalize_domain_ids(ids) when is_list(ids), do: Enum.uniq(ids)
  defp normalize_domain_ids(_other), do: []

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp format_error(reason) when is_binary(reason), do: String.slice(reason, 0, 500)
  defp format_error(reason), do: inspect(reason) |> String.slice(0, 500)

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  end
end
