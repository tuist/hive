defmodule Hive.Drops do
  @moduledoc """
  Shipped-update entries from GitHub release drop items and RSS/Atom
  changelogs. Drops are read-only from the dashboard's perspective;
  their data is reconciled by the `Hive.Drops.GitHubReleasesSyncer` and
  `Hive.Drops.RssSyncer`, and routed to domains by
  `Hive.Drops.DomainClassification`.

  A drop has a many-to-many relationship with domains. A drop is
  visible to anonymous viewers when any of its domains is public, and
  to organization members across the board.

  Source management (the RSS/Atom URLs operators register) is
  admin-only and lives behind `Hive.Ops.Policy`. See
  `Hive.Drops.DropSource`.
  """

  use Gettext, backend: HiveWeb.Gettext
  use HiveWeb, :verified_routes

  import Ecto.Query

  alias Hive.Auth
  alias Hive.Drops.Drop
  alias Hive.Drops.DropDomain
  alias Hive.Drops.DropGitHubIssue
  alias Hive.Drops.DropSource
  alias Hive.Drops.GitHubReleaseIngestion
  alias Hive.Domains.Domain
  alias Hive.Domains.GitHubRepository
  alias Hive.Forage.GitHubIssue
  alias Hive.Projects.Project
  alias Hive.Projects.ProjectDomain
  alias Hive.Repo

  @default_page_size 20
  @release_retry_base_seconds :timer.minutes(15) |> div(1_000)
  @release_retry_max_seconds :timer.hours(24) |> div(1_000)
  # PostgreSQL advisory locks need stable application-defined integer keys.
  @drop_number_lock_namespace :binary.decode_unsigned("Hive")
  @drop_number_lock_key :binary.decode_unsigned("DROP")
  @drop_attr_keys [
    :source_type,
    :external_id,
    :title,
    :body,
    :url,
    :version,
    :published_at,
    :classified_at,
    :drop_source_id,
    :github_repository_id
  ]
  @drop_attr_key_map Map.new(@drop_attr_keys, &{Atom.to_string(&1), &1})
  @github_release_ingestion_attr_keys [
    :release_key,
    :release_fingerprint,
    :status,
    :items_count,
    :attempt_count,
    :last_error,
    :next_attempt_at,
    :processed_at
  ]
  @github_release_ingestion_attr_key_map Map.new(
                                           @github_release_ingestion_attr_keys,
                                           &{Atom.to_string(&1), &1}
                                         )

  @doc "Returns true when a GitHub release has already been evaluated for drop items."
  def github_release_processed?(%GitHubRepository{} = repository, release_key)
      when is_binary(release_key) do
    github_release_ingestion_exists?(repository, release_key) or
      github_release_drop_exists?(repository, release_key)
  end

  @doc "Returns true when a release fingerprint should be evaluated now."
  def github_release_due?(
        %GitHubRepository{} = repository,
        release_key,
        release_fingerprint,
        now \\ DateTime.utc_now()
      )
      when is_binary(release_key) and is_binary(release_fingerprint) do
    case github_release_ingestion(repository, release_key) do
      %GitHubReleaseIngestion{} = ingestion ->
        release_ingestion_due?(ingestion, release_fingerprint, now)

      nil ->
        not github_release_drop_exists?(repository, release_key)
    end
  end

  @doc "Records that a GitHub release was evaluated for drop items."
  def record_github_release_ingestion(%GitHubRepository{} = repository, attrs)
      when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = normalize_github_release_ingestion_attrs(attrs)
    release_key = Map.fetch!(attrs, :release_key)

    attrs =
      attrs
      |> Map.put(:github_repository_id, repository.id)
      |> Map.put(:release_key_hash, hash_value(release_key))
      |> Map.put_new(:attempt_count, 0)
      |> Map.put_new(:processed_at, now)

    %GitHubReleaseIngestion{}
    |> GitHubReleaseIngestion.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :release_key,
           :release_fingerprint,
           :status,
           :items_count,
           :attempt_count,
           :last_error,
           :next_attempt_at,
           :processed_at,
           :updated_at
         ]},
      conflict_target: [:github_repository_id, :release_key_hash],
      returning: true
    )
  end

  @doc "Records a failed release evaluation and schedules a bounded retry."
  def record_github_release_failure(
        %GitHubRepository{} = repository,
        release_key,
        release_fingerprint,
        reason,
        opts \\ []
      )
      when is_binary(release_key) and is_binary(release_fingerprint) and is_list(opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    retry? = Keyword.get(opts, :retry?, true)

    attempt_count =
      case github_release_ingestion(repository, release_key) do
        %GitHubReleaseIngestion{release_fingerprint: ^release_fingerprint, attempt_count: count} ->
          count + 1

        _ingestion ->
          1
      end

    record_github_release_ingestion(repository, %{
      release_key: release_key,
      release_fingerprint: release_fingerprint,
      status: if(retry?, do: :failed, else: :rejected),
      items_count: 0,
      attempt_count: attempt_count,
      last_error: format_error(reason),
      next_attempt_at:
        if(retry?, do: DateTime.add(now, release_retry_seconds(attempt_count), :second)),
      processed_at: now
    })
  end

  @doc "Lists drops the `user` can see, paginated and optionally filtered by projects or domains."
  def list_drops(opts \\ []) do
    user = Keyword.get(opts, :user)
    page = Keyword.get(opts, :page, 1) |> max(1)
    page_size = Keyword.get(opts, :page_size, @default_page_size) |> normalize_page_size()
    domain_ids = Keyword.get(opts, :domain_ids, []) |> normalize_domain_ids()
    project_ids = Keyword.get(opts, :project_ids, []) |> normalize_project_ids()
    query_text = Keyword.get(opts, :query)
    source_type = Keyword.get(opts, :source_type)

    base =
      Drop
      |> apply_visibility(user)
      |> filter_domain_ids(domain_ids)
      |> filter_project_ids(project_ids)
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
      |> preload(^drop_preloads())
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
    |> preload(^drop_preloads())
    |> Repo.all()
  end

  @doc "Lists drops for a single project ordered by `published_at` descending."
  def list_drops_for_project(%Project{} = project, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    user = Keyword.get(opts, :user)

    Drop
    |> apply_visibility(user)
    |> filter_project_ids([project.id])
    |> distinct(true)
    |> order_by([drop], desc: drop.published_at, desc: drop.inserted_at)
    |> limit(^limit)
    |> preload(^drop_preloads())
    |> Repo.all()
  end

  @doc "Lists GitHub-release drops linked to a cached GitHub issue forage item."
  def list_release_drops_for_github_issue(%GitHubIssue{} = issue, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Drop
    |> join(:inner, [drop], link in DropGitHubIssue,
      on: link.drop_id == drop.id and link.forage_github_issue_id == ^issue.id
    )
    |> where([drop], drop.source_type == :github_release)
    |> order_by([drop], desc: drop.published_at, desc: drop.inserted_at)
    |> limit(^limit)
    |> preload(^drop_preloads())
    |> Repo.all()
  end

  @doc "Fetches a drop by public number, shared URL, or internal id when the `user` can see it."
  def fetch_visible_drop(reference, user) when is_integer(reference),
    do: fetch_visible_drop_by_number(reference, user)

  def fetch_visible_drop(reference, user) when is_binary(reference) do
    reference
    |> reference_identifier()
    |> case do
      "" ->
        {:error, :not_found}

      identifier ->
        if public_number?(identifier),
          do: fetch_visible_drop_by_number(identifier, user),
          else: fetch_visible_drop_by_internal_id(identifier, user)
    end
  end

  def public_path(%Drop{number: number}) when is_integer(number), do: ~p"/drops/#{number}"

  @doc "Idempotently inserts or updates a drop based on the unique (source_type, external_id)."
  def upsert_drop(attrs) when is_map(attrs) do
    attrs = normalize_drop_attrs(attrs)

    Repo.transaction(fn ->
      %Drop{}
      |> Drop.changeset(attrs)
      |> put_next_drop_number()
      |> Repo.insert(
        on_conflict: {:replace, [:title, :body, :url, :published_at, :updated_at]},
        conflict_target: [:source_type, :external_id],
        returning: true
      )
      |> case do
        {:ok, drop} -> drop
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_drop(id) when is_binary(id) do
    case Repo.get(Drop, id) do
      nil ->
        nil

      %Drop{} = drop ->
        Repo.preload(drop, drop_preloads())
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

  @doc "Replaces the GitHub issue forage links for a drop."
  def replace_drop_github_issues(%Drop{} = drop, issue_ids) when is_list(issue_ids) do
    inserted_at = DateTime.utc_now() |> DateTime.truncate(:second)

    selected =
      issue_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    rows =
      Enum.map(selected, fn issue_id ->
        %{
          drop_id: drop.id,
          forage_github_issue_id: issue_id,
          inserted_at: inserted_at,
          updated_at: inserted_at
        }
      end)

    Repo.transaction(fn ->
      from(link in DropGitHubIssue, where: link.drop_id == ^drop.id)
      |> Repo.delete_all()

      if rows != [], do: Repo.insert_all(DropGitHubIssue, rows)
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

  def get_drop_source(id) when is_binary(id) do
    Repo.get(DropSource, id)
  rescue
    Ecto.Query.CastError -> nil
  end

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

  def source_type_label(:github_release), do: dgettext("dashboard_drops", "GitHub")
  def source_type_label(:rss), do: dgettext("dashboard_drops", "RSS")
  def source_type_label(value) when is_atom(value), do: value |> Atom.to_string()
  def source_type_label(_value), do: dgettext("dashboard_drops", "Drop")

  defp drop_preloads do
    [
      domains: :projects,
      github_repository: :project,
      github_issues: :github_repository,
      drop_source: :project
    ]
  end

  @doc """
  Returns the projects a drop belongs to, first through assigned domains
  and then through its source repository or feed.
  """
  def projects_for_drop(%Drop{} = drop) do
    drop
    |> domain_projects()
    |> Kernel.++([source_project(drop)])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&project_key/1)
  end

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

  defp filter_project_ids(query, []), do: query

  defp filter_project_ids(query, ids) when is_list(ids) do
    query
    |> join(:left, [drop], repository in assoc(drop, :github_repository),
      as: :project_filter_repository
    )
    |> join(:left, [drop], source in assoc(drop, :drop_source), as: :project_filter_source)
    |> join(:left, [drop], project_filter_domain_link in DropDomain,
      on: project_filter_domain_link.drop_id == drop.id,
      as: :project_filter_domain_link
    )
    |> join(:left, [project_filter_domain_link: domain_link], project_domain in ProjectDomain,
      on: project_domain.domain_id == domain_link.domain_id,
      as: :project_filter_domain
    )
    |> where(
      [
        project_filter_repository: repository,
        project_filter_source: source,
        project_filter_domain: project_domain
      ],
      repository.project_id in ^ids or source.project_id in ^ids or
        project_domain.project_id in ^ids
    )
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

  defp fetch_visible_drop_by_number(number, user) when is_binary(number) do
    case Integer.parse(number) do
      {number, ""} -> fetch_visible_drop_by_number(number, user)
      _invalid -> {:error, :not_found}
    end
  end

  defp fetch_visible_drop_by_number(number, user) when is_integer(number) do
    case Repo.get_by(Drop, number: number) do
      nil ->
        {:error, :not_found}

      %Drop{} = drop ->
        drop =
          Repo.preload(drop, drop_preloads())

        if visible?(drop, user),
          do: {:ok, drop},
          else: {:error, :not_found}
    end
  end

  defp fetch_visible_drop_by_internal_id(id, user) do
    case Repo.get(Drop, id) do
      nil ->
        {:error, :not_found}

      %Drop{} = drop ->
        drop =
          Repo.preload(drop, drop_preloads())

        if visible?(drop, user),
          do: {:ok, drop},
          else: {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp reference_identifier(reference) do
    reference = String.trim(reference)

    case URI.parse(reference) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> drop_path_number()
        |> Kernel.||(reference)

      _uri ->
        reference
    end
  end

  defp drop_path_number(["drops", number | _rest]), do: number
  defp drop_path_number([_segment | rest]), do: drop_path_number(rest)
  defp drop_path_number([]), do: nil

  defp public_number?(identifier) do
    match?({_number, ""}, Integer.parse(identifier))
  end

  defp normalize_page_size(size) when is_integer(size) and size > 0 and size <= 100, do: size
  defp normalize_page_size(:all), do: 10_000
  defp normalize_page_size(_size), do: @default_page_size

  defp github_release_ingestion_exists?(%GitHubRepository{id: repository_id}, release_key) do
    release_key_hash = hash_value(release_key)

    GitHubReleaseIngestion
    |> where(
      [ingestion],
      ingestion.github_repository_id == ^repository_id and
        ingestion.release_key_hash == ^release_key_hash and
        ingestion.status in [:generated, :ignored, :rejected]
    )
    |> Repo.exists?()
  end

  defp github_release_drop_exists?(%GitHubRepository{id: repository_id}, release_key) do
    Drop
    |> where(
      [drop],
      drop.source_type == :github_release and
        drop.github_repository_id == ^repository_id and
        drop.version == ^release_key
    )
    |> Repo.exists?()
  end

  defp normalize_domain_ids(nil), do: []
  defp normalize_domain_ids(ids) when is_list(ids), do: Enum.uniq(ids)
  defp normalize_domain_ids(_other), do: []

  defp normalize_project_ids(nil), do: []
  defp normalize_project_ids(ids) when is_list(ids), do: Enum.uniq(ids)
  defp normalize_project_ids(_other), do: []

  defp domain_projects(%{domains: %Ecto.Association.NotLoaded{}}), do: []
  defp domain_projects(%{domains: nil}), do: []

  defp domain_projects(%{domains: domains}) when is_list(domains),
    do: Enum.flat_map(domains, &loaded_projects/1)

  defp domain_projects(_drop), do: []

  defp source_project(drop) do
    loaded_project(Map.get(drop, :github_repository)) ||
      loaded_project(Map.get(drop, :drop_source))
  end

  defp loaded_project(%{project: %Ecto.Association.NotLoaded{}}), do: nil
  defp loaded_project(%{project: nil}), do: nil
  defp loaded_project(%{project: project}), do: project
  defp loaded_project(_record), do: nil

  defp loaded_projects(%{projects: %Ecto.Association.NotLoaded{}}), do: []
  defp loaded_projects(%{projects: projects}) when is_list(projects), do: projects
  defp loaded_projects(record), do: List.wrap(loaded_project(record)) |> Enum.reject(&is_nil/1)

  defp project_key(%{id: id}) when is_binary(id), do: id
  defp project_key(%{name: name}), do: name

  defp put_next_drop_number(%Ecto.Changeset{valid?: true} = changeset) do
    lock_drops_for_numbering()
    Ecto.Changeset.put_change(changeset, :number, next_drop_number())
  end

  defp put_next_drop_number(%Ecto.Changeset{} = changeset), do: changeset

  defp lock_drops_for_numbering do
    Repo.query!(
      "SELECT pg_advisory_xact_lock($1::integer, $2::integer)",
      [@drop_number_lock_namespace, @drop_number_lock_key]
    )
  end

  defp next_drop_number do
    Repo.one!(from(drop in Drop, select: fragment("COALESCE(MAX(?), 0) + 1", drop.number)))
  end

  defp escape_like(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp format_error(reason) when is_binary(reason), do: String.slice(reason, 0, 500)
  defp format_error(reason), do: inspect(reason) |> String.slice(0, 500)

  defp hash_value(value) when is_binary(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end

  defp github_release_ingestion(%GitHubRepository{id: repository_id}, release_key) do
    Repo.get_by(GitHubReleaseIngestion,
      github_repository_id: repository_id,
      release_key_hash: hash_value(release_key)
    )
  end

  defp release_ingestion_due?(
         %GitHubReleaseIngestion{release_fingerprint: fingerprint},
         release_fingerprint,
         _now
       )
       when fingerprint != release_fingerprint,
       do: true

  defp release_ingestion_due?(
         %GitHubReleaseIngestion{status: status},
         _release_fingerprint,
         _now
       )
       when status in [:generated, :ignored, :rejected],
       do: false

  defp release_ingestion_due?(
         %GitHubReleaseIngestion{status: :failed, next_attempt_at: nil},
         _release_fingerprint,
         _now
       ),
       do: true

  defp release_ingestion_due?(
         %GitHubReleaseIngestion{status: :failed, next_attempt_at: next_attempt_at},
         _release_fingerprint,
         now
       ),
       do: DateTime.compare(next_attempt_at, now) != :gt

  defp release_retry_seconds(attempt_count) do
    exponent = min(max(attempt_count - 1, 0), 10)
    min(@release_retry_base_seconds * Integer.pow(2, exponent), @release_retry_max_seconds)
  end

  defp normalize_drop_attrs(map) when is_map(map) do
    Enum.reduce(map, %{}, &put_known_drop_attr/2)
  end

  defp normalize_github_release_ingestion_attrs(map) when is_map(map) do
    Enum.reduce(map, %{}, &put_known_github_release_ingestion_attr/2)
  end

  defp put_known_github_release_ingestion_attr({key, value}, acc)
       when key in @github_release_ingestion_attr_keys,
       do: Map.put(acc, key, value)

  defp put_known_github_release_ingestion_attr({key, value}, acc) when is_binary(key) do
    case Map.fetch(@github_release_ingestion_attr_key_map, key) do
      {:ok, attr} -> Map.put(acc, attr, value)
      :error -> acc
    end
  end

  defp put_known_github_release_ingestion_attr(_entry, acc), do: acc

  defp put_known_drop_attr({key, value}, acc) when key in @drop_attr_keys,
    do: Map.put(acc, key, value)

  defp put_known_drop_attr({key, value}, acc) when is_binary(key) do
    case Map.fetch(@drop_attr_key_map, key) do
      {:ok, attr} -> Map.put(acc, attr, value)
      :error -> acc
    end
  end

  defp put_known_drop_attr(_entry, acc), do: acc
end
