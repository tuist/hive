defmodule Hive.Forage do
  @moduledoc """
  Collects sources that can feed Hive with workable pieces of work.
  """

  import Ecto.Query

  alias Hive.Accounts.User
  alias Hive.Auth
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.Grafana
  alias Hive.Forage.Policy
  alias Hive.Meadows.GitHubRepository
  alias Hive.Meadows.Meadow
  alias Hive.Repo

  @sources [
    %{
      id: :feature_requests,
      label: "Feature requests",
      description: "Public meadow ideas submitted by authenticated users.",
      icon: "bulb",
      path: "/forage/feature-requests",
      visibility: :public,
      creatable?: true
    },
    %{
      id: :bug_reports,
      label: "Bug reports",
      description: "Public defects that should become actionable work.",
      icon: "file_alert",
      path: "/forage/bug-reports",
      visibility: :public,
      creatable?: true
    },
    %{
      id: :feedback,
      label: "Feedback",
      description: "Public feedback that helps shape the meadow direction.",
      icon: "message_circle",
      path: "/forage/feedback",
      visibility: :public,
      creatable?: true
    },
    %{
      id: :github_issues,
      label: "GitHub issues",
      description: "Open issues from the GitHub repositories connected to your meadows.",
      icon: "brand_github",
      path: "/forage/github-issues",
      visibility: :per_meadow,
      creatable?: false
    },
    %{
      id: :grafana_alerts,
      label: "Grafana alerts",
      description: "Operational signals visible only to organization members.",
      icon: "bell",
      path: "/forage/grafana-alerts",
      visibility: :organization,
      creatable?: false
    }
  ]

  def sources, do: @sources

  def visible_sources(user) do
    Enum.filter(@sources, &can_access?(&1, user))
  end

  def get_source!(id) do
    Enum.find(@sources, &(&1.id == id)) || raise ArgumentError, "unknown forage source: #{id}"
  end

  def can_access?(%{visibility: :per_meadow}, user) do
    Auth.member?(user) or accessible_meadows_with_repositories(user) != []
  end

  def can_access?(source, user) do
    Policy.authorize?(:forage_source_read, user, source)
  end

  def can_create?(source, user) do
    Policy.authorize?(:forage_source_create, user, source)
  end

  @doc """
  Returns `{meadow, repository}` tuples that the user is allowed to see.
  Effective visibility is the most restrictive of the two: a private
  repository hides the pair from anyone outside the organization, even if
  the meadow itself is public.
  """
  def accessible_meadows_with_repositories(user) do
    Meadow
    |> preload(:github_repositories)
    |> Repo.all()
    |> Enum.flat_map(fn meadow ->
      Enum.map(meadow.github_repositories, &{meadow, &1})
    end)
    |> Enum.filter(fn {meadow, repository} -> accessible_pair?(meadow, repository, user) end)
  end

  defp accessible_pair?(meadow, repository, user) do
    case effective_visibility(meadow, repository) do
      :public -> true
      :private -> Auth.member?(user)
    end
  end

  defp effective_visibility(%{visibility: :private}, _repository), do: :private
  defp effective_visibility(_meadow, %{visibility: :private}), do: :private
  defp effective_visibility(_meadow, _repository), do: :public

  def list_feature_requests do
    FeatureRequest
    |> order_by([feature_request], desc: feature_request.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def get_feature_request!(id) do
    FeatureRequest
    |> preload(:user)
    |> Repo.get!(id)
  end

  def change_feature_request(feature_request \\ %FeatureRequest{}, attrs \\ %{}) do
    FeatureRequest.changeset(feature_request, attrs)
  end

  def create_feature_request(attrs, %User{} = user) do
    %FeatureRequest{}
    |> FeatureRequest.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
    |> case do
      {:ok, feature_request} ->
        Hive.Meadows.schedule_evolution()
        {:ok, feature_request}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defdelegate list_grafana_alerts, to: Grafana, as: :list_alerts

  @doc """
  Returns `{meadow, repository, issue}` triples for every cached GitHub
  issue the user is allowed to see. Visibility is enforced through
  `accessible_meadows_with_repositories/1`, so private repos stay hidden
  from anyone outside the organization.

  Options:
  - `:state` (default `:open`) — filter by issue state
  - `:meadow_id` — restrict to one meadow
  - `:repository_id` — restrict to one repository
  """
  def list_github_issues_for_user(user, opts \\ []) do
    state = Keyword.get(opts, :state, :open)
    meadow_id = Keyword.get(opts, :meadow_id)
    repository_id = Keyword.get(opts, :repository_id)

    pairs =
      user
      |> accessible_meadows_with_repositories()
      |> Enum.filter(fn {meadow, repository} ->
        (is_nil(meadow_id) or meadow.id == meadow_id) and
          (is_nil(repository_id) or repository.id == repository_id)
      end)

    repository_ids = Enum.map(pairs, fn {_meadow, repository} -> repository.id end)

    issues =
      GitHubIssue
      |> where([issue], issue.github_repository_id in ^repository_ids)
      |> maybe_filter_by_state(state)
      |> order_by([issue], desc: issue.updated_at)
      |> Repo.all()

    pairs_by_repository_id =
      Map.new(pairs, fn {meadow, repository} -> {repository.id, {meadow, repository}} end)

    Enum.flat_map(issues, fn issue ->
      case Map.fetch(pairs_by_repository_id, issue.github_repository_id) do
        {:ok, {meadow, repository}} -> [{meadow, repository, issue}]
        :error -> []
      end
    end)
  end

  defp maybe_filter_by_state(query, nil), do: query
  defp maybe_filter_by_state(query, state), do: where(query, [issue], issue.state == ^state)

  @doc """
  Replaces the cached open issues for a single repository with `entries`.
  Each entry is a map with `:number`, `:title`, and `:body`. Issues that
  exist in the cache but are absent from `entries` are removed so the
  cache reflects only currently-open issues.
  """
  def reconcile_repository_github_issues(%GitHubRepository{id: repository_id}, entries) do
    incoming_numbers = entries |> Enum.map(& &1.number) |> Enum.uniq()

    Repo.transaction(fn ->
      Enum.each(entries, &upsert_entry(repository_id, &1))
      delete_missing(repository_id, incoming_numbers)
    end)

    Hive.Meadows.schedule_evolution()

    :ok
  end

  defp upsert_entry(repository_id, entry) do
    attrs = %{
      github_repository_id: repository_id,
      number: entry.number,
      title: entry.title,
      body: entry.body,
      state: Map.get(entry, :state, :open)
    }

    existing = Repo.get_by(GitHubIssue, github_repository_id: repository_id, number: entry.number)

    (existing || %GitHubIssue{})
    |> GitHubIssue.changeset(attrs)
    |> Repo.insert_or_update!()
  end

  defp delete_missing(repository_id, []) do
    GitHubIssue
    |> where([issue], issue.github_repository_id == ^repository_id)
    |> Repo.delete_all()
  end

  defp delete_missing(repository_id, numbers) do
    GitHubIssue
    |> where([issue], issue.github_repository_id == ^repository_id)
    |> where([issue], issue.number not in ^numbers)
    |> Repo.delete_all()
  end

  def list_repositories_with_meadows do
    Meadow
    |> preload(:github_repositories)
    |> Repo.all()
    |> Enum.flat_map(fn meadow ->
      Enum.map(meadow.github_repositories, &{meadow, &1})
    end)
  end
end
