defmodule Hive.Drops.GitHubReleasesSyncer do
  @moduledoc """
  Periodically reconciles the `drops` table with user-facing drop items
  generated from the latest releases from every GitHub repository
  connected to a domain.

  The worker is scheduled from Oban's cron configuration. When the GitHub
  App is not configured it logs and skips, mirroring
  `Hive.Forage.GitHubIssueSyncer`.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  require Logger

  import Ecto.Query

  alias Hive.Audit
  alias Hive.Drops
  alias Hive.Drops.DomainClassificationWorker
  alias Hive.Drops.ReleaseDropItems
  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.GitHub.Client
  alias Hive.GitHub.IssueRefs
  alias Hive.GitHub.Issues
  alias Hive.GitHub.Releases
  alias Hive.Domains.GitHubRepository
  alias Hive.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case sync_now() do
      :skipped -> :ok
      result -> result
    end
  end

  @doc "Runs the GitHub releases sync immediately and returns when it finishes."
  def sync_now(opts \\ []) do
    state = %{
      generator_opts: Keyword.get(opts, :generator_opts, []),
      item_generator: Keyword.get(opts, :item_generator, &ReleaseDropItems.generate/3)
    }

    run_sync(state)
  end

  defp run_sync(state) do
    case Client.config() do
      {:ok, _config} ->
        Audit.put_context(%{interface: "worker"})

        list_project_repositories()
        |> Enum.each(&sync_project_repository(&1, state))

        :ok

      {:error, {:not_configured, _missing}} ->
        Logger.debug("[Drops.GitHubReleasesSyncer] GitHub App not configured; skipping")
        :skipped
    end
  end

  defp list_project_repositories do
    query =
      from(repository in GitHubRepository,
        where: not is_nil(repository.project_id),
        preload: [project: :domains]
      )

    Repo.all(query)
  end

  defp sync_project_repository(%GitHubRepository{project: project} = repository, state) do
    domains = project.domains

    case Releases.list_releases(repository) do
      {:ok, releases} ->
        Enum.each(releases, fn release ->
          upsert_release_items(domains, repository, release, state)
        end)

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to sync #{repository.owner}/#{repository.name}: " <>
            inspect(reason)
        )
    end
  end

  defp upsert_release_items(domains, repository, %Releases{} = release, state) do
    case state.item_generator.(repository, release, state.generator_opts) do
      {:ok, items} ->
        Enum.each(items, fn item ->
          upsert_release_item_drop(domains, repository, release, item)
        end)

      :skipped ->
        Logger.debug(
          "[Drops.GitHubReleasesSyncer] Skipping release #{release_label(repository, release)} because release drop item generation is unavailable"
        )

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to generate drop items for release " <>
            release_label(repository, release) <> ": " <> inspect(reason)
        )
    end
  end

  defp upsert_release_item_drop(domains, repository, release, item) do
    attrs = %{
      github_repository_id: repository.id,
      source_type: :github_release,
      external_id: release_item_external_id(repository, release, item),
      title: item.title,
      body: item.body,
      url: item_url(item, release),
      published_at: parse_timestamp(release.published_at || release.created_at),
      version: release.tag_name
    }

    case Drops.upsert_drop(attrs) do
      {:ok, drop} ->
        drop
        |> link_release_item_github_issues(repository, item)

        record_audit(drop, domains, repository, release, item)

        if is_nil(drop.classified_at) do
          DomainClassificationWorker.enqueue(drop.id)
        end

        :ok

      {:error, reason} ->
        Logger.warning(
          "[Drops.GitHubReleasesSyncer] Failed to upsert release drop item " <>
            inspect(item.title) <> ": " <> inspect(reason)
        )
    end
  end

  defp link_release_item_github_issues(drop, repository, item) do
    issue_ids =
      item
      |> release_item_issue_refs(repository)
      |> Enum.flat_map(&fetch_or_upsert_issue(&1, repository))
      |> Enum.map(& &1.id)

    Drops.replace_drop_github_issues(drop, issue_ids)
  end

  defp release_item_issue_refs(item, repository) do
    item.source_urls
    |> Enum.join("\n")
    |> IssueRefs.extract(default_repo: {repository.owner, repository.name}, limit: 10)
  end

  defp fetch_or_upsert_issue(ref, source_repository) do
    case repository_for_ref(ref, source_repository) do
      %GitHubRepository{} = repository ->
        case Repo.get_by(GitHubIssue, github_repository_id: repository.id, number: ref.number) do
          %GitHubIssue{} = issue ->
            [issue]

          nil ->
            fetch_and_upsert_issue(repository, ref)
        end

      nil ->
        []
    end
  end

  defp fetch_and_upsert_issue(repository, ref) do
    with {:ok, issue} <- Issues.get_issue(repository, ref.number),
         {:ok, forage_issue} <- Forage.upsert_repository_github_issue(repository, issue) do
      [forage_issue]
    else
      {:error, reason} ->
        log_reference_link_failure(ref, reason)
        []
    end
  end

  defp log_reference_link_failure(ref, reason) do
    Logger.debug(
      "[Drops.GitHubReleasesSyncer] Failed to link release reference " <>
        "#{ref.owner}/#{ref.name}##{ref.number}: " <> inspect(reason)
    )
  end

  defp repository_for_ref(ref, %GitHubRepository{owner: owner, name: name} = repository) do
    if ref.owner == owner and ref.name == name do
      repository
    else
      Repo.get_by(GitHubRepository, owner: ref.owner, name: ref.name)
    end
  end

  defp record_audit(drop, domains, repository, release, item) do
    if drop.inserted_at == drop.updated_at do
      Audit.record(:"drop.ingested", %{
        target_type: "drop",
        target_id: drop.id,
        target_label: drop.title,
        metadata: %{
          source_type: "github_release",
          repository: "#{repository.owner}/#{repository.name}",
          release: release.tag_name,
          references: item.source_urls,
          domains: Enum.map_join(domains, ", ", & &1.name),
          number: to_string(drop.number),
          path: Drops.public_path(drop)
        }
      })
    end
  end

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(""), do: nil

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_timestamp(_value), do: nil

  defp release_item_external_id(repository, release, item) do
    release_key =
      release.tag_name || release.html_url || release.published_at || release.created_at ||
        "untagged"

    item_key =
      item.source_urls
      |> Enum.sort()
      |> Enum.join("\n")
      |> hash_key()

    "#{repository.owner}/#{repository.name}@#{release_key}:#{item_key}"
  end

  defp release_label(repository, release) do
    release_key = release.tag_name || release.html_url || release.published_at || "untagged"
    "#{repository.owner}/#{repository.name}@#{release_key}"
  end

  defp item_url(item, release) do
    Enum.find(item.source_urls, &github_issue_or_pull_url?/1) ||
      List.first(item.source_urls) ||
      release.html_url
  end

  defp github_issue_or_pull_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, path: path}
      when scheme in ["http", "https"] and is_binary(host) and is_binary(path) ->
        host = String.downcase(host)
        path_parts = path |> String.trim_leading("/") |> String.split("/")

        host in ["github.com", "www.github.com"] and github_issue_or_pull_path?(path_parts)

      _other ->
        false
    end
  end

  defp github_issue_or_pull_url?(_url), do: false

  defp github_issue_or_pull_path?([_owner, _name, type, number | _rest])
       when type in ["issues", "pull"] do
    match?({_number, ""}, Integer.parse(number))
  end

  defp github_issue_or_pull_path?(_path_parts), do: false

  defp hash_key(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
