defmodule Hive.Drops do
  @moduledoc """
  Shipped-update entries from GitHub release drop items and RSS/Atom
  changelogs. Drops are read-only from the dashboard's perspective;
  their data is reconciled by the `Hive.Drops.GitHubReleasesSyncer` and
  `Hive.Drops.RssSyncer`, and routed to meadows by
  `Hive.Drops.MeadowClassification`.

  A drop has a many-to-many relationship with meadows. A drop is
  visible to anonymous viewers when any of its meadows is public, and
  to organization members across the board.

  Source management (the RSS/Atom URLs operators register) is
  admin-only and lives behind `Hive.Ops.Policy`. See
  `Hive.Drops.DropSource`.
  """

  import Ecto.Query

  alias Hive.Auth
  alias Hive.Drops.Drop
  alias Hive.Drops.DropMeadow
  alias Hive.Drops.DropSource
  alias Hive.Meadows.Meadow
  alias Hive.Repo

  @default_page_size 20

  @doc "Lists drops the `user` can see, paginated and optionally filtered by meadows."
  def list_drops(opts \\ []) do
    user = Keyword.get(opts, :user)
    page = Keyword.get(opts, :page, 1) |> max(1)
    page_size = Keyword.get(opts, :page_size, @default_page_size) |> normalize_page_size()
    meadow_ids = Keyword.get(opts, :meadow_ids, []) |> normalize_meadow_ids()
    query_text = Keyword.get(opts, :query)
    source_type = Keyword.get(opts, :source_type)

    base =
      Drop
      |> apply_visibility(user)
      |> filter_meadow_ids(meadow_ids)
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
      |> preload(meadows: :project, github_repository: [], drop_source: [])
      |> Repo.all()

    {entries,
     %{
       current_page: page,
       page_size: page_size,
       total_entries: total_entries,
       total_pages: total_pages
     }}
  end

  @doc "Lists drops for a single meadow ordered by `published_at` descending."
  def list_drops_for_meadow(%Meadow{} = meadow, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Drop
    |> join(:inner, [drop], dm in DropMeadow,
      on: dm.drop_id == drop.id and dm.meadow_id == ^meadow.id
    )
    |> order_by([drop], desc: drop.published_at, desc: drop.inserted_at)
    |> limit(^limit)
    |> preload(meadows: :project, github_repository: [], drop_source: [])
    |> Repo.all()
  end

  @doc "Fetches a drop by id when the `user` is allowed to see it."
  def fetch_visible_drop(id, user) when is_binary(id) do
    case Repo.get(Drop, id) do
      nil ->
        {:error, :not_found}

      %Drop{} = drop ->
        drop = Repo.preload(drop, [:meadows, :github_repository, :drop_source])

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

  def get_drop(id) when is_binary(id) do
    case Repo.get(Drop, id) do
      nil -> nil
      %Drop{} = drop -> Repo.preload(drop, [:meadows, :github_repository, :drop_source])
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  @doc """
  Replaces the meadow links for `drop` with the given `meadow_ids` and
  stamps `classified_at` so the sweeper does not pick the row up again.
  Passes through the list of meadow ids that were actually linked.
  """
  def replace_drop_meadows(%Drop{} = drop, meadow_ids) when is_list(meadow_ids) do
    classified_at = DateTime.utc_now() |> DateTime.truncate(:second)

    selected =
      meadow_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    inserted_at = classified_at

    rows =
      Enum.map(selected, fn meadow_id ->
        %{
          drop_id: drop.id,
          meadow_id: meadow_id,
          inserted_at: inserted_at,
          updated_at: inserted_at
        }
      end)

    Repo.transaction(fn ->
      from(link in DropMeadow, where: link.drop_id == ^drop.id)
      |> Repo.delete_all()

      if rows != [], do: Repo.insert_all(DropMeadow, rows)

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
    meadows = drop.meadows || Repo.preload(drop, :meadows).meadows

    cond do
      Auth.member?(user) -> true
      Enum.any?(meadows, &(&1.visibility == :public)) -> true
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
      |> join(:left, [drop], dm in DropMeadow, on: dm.drop_id == drop.id, as: :meadow_link)
    else
      query
      |> join(:inner, [drop], dm in DropMeadow, on: dm.drop_id == drop.id, as: :meadow_link)
      |> join(:inner, [meadow_link: dm], meadow in Meadow,
        on: meadow.id == dm.meadow_id and meadow.visibility == :public,
        as: :public_meadow
      )
    end
  end

  defp filter_meadow_ids(query, []), do: query

  defp filter_meadow_ids(query, ids) when is_list(ids) do
    where(query, [meadow_link: dm], dm.meadow_id in ^ids)
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

  defp normalize_meadow_ids(nil), do: []
  defp normalize_meadow_ids(ids) when is_list(ids), do: Enum.uniq(ids)
  defp normalize_meadow_ids(_other), do: []

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp format_error(reason) when is_binary(reason), do: String.slice(reason, 0, 500)
  defp format_error(reason), do: inspect(reason) |> String.slice(0, 500)
end
