defmodule Hive.Forage.GitHubIssueClassification do
  @moduledoc """
  Resolves which domains a single GitHub issue belongs to and persists the
  resulting links.

  Classification calls the configured LLM through
  `Hive.Forage.Agents.GitHubIssueClassifierAgent`. The candidate set is
  the domains attached to the issue's repository, so the answer is always
  a subset of that list. When the LLM is not configured, every candidate
  domain is linked so the dashboard still has something to show.
  """

  import Ecto.Query

  alias Hive.Agents
  alias Hive.Agents.Errors
  alias Hive.Agents.Sessions
  alias Hive.Forage.Agents.GitHubIssueClassifierAgent
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueDomain
  alias Hive.Domains.Domain
  alias Hive.Domains.GitHubRepository
  alias Hive.Projects.ProjectDomain
  alias Hive.Repo

  @business_context """
  Tuist builds infrastructure for productive software development, including
  caching, compute environments, and support for build systems such as Xcode,
  Gradle, and Bazel. Important domains include build automation, remote caching,
  testing, CI, release workflows, developer experience, documentation, Atlas
  operations, Hive product planning, forage, specs, MCP, identity, and Once
  distribution.
  """

  @max_body_length 500
  @max_domain_description_length 200

  @doc """
  Classifies the issue with `issue_id` and writes the resulting domain
  links.

  Returns `{:ok, [domain_id]}` on success, `{:error, :not_found}` for an
  unknown id, and `{:error, reason}` for an LLM error that should be
  retried by the caller (typically the worker).
  """
  def classify(issue_id, opts \\ []) when is_binary(issue_id) do
    case load_issue(issue_id) do
      nil -> {:error, :not_found}
      issue -> classify_issue(issue, opts)
    end
  end

  def classify_issue(%GitHubIssue{} = issue, opts \\ []) do
    candidate_domains = candidate_domains(issue.github_repository_id)

    cond do
      candidate_domains == [] ->
        # Leave classified_at nil so the sweeper retries once the
        # repository is attached to its first domain.
        {:ok, []}

      not agents_enabled?(opts) ->
        domain_ids = Enum.map(candidate_domains, & &1.id)
        persist!(issue, domain_ids)
        {:ok, domain_ids}

      true ->
        run_agent(issue, candidate_domains, opts)
    end
  end

  defp run_agent(issue, candidate_domains, opts) do
    runner = Keyword.get(opts, :runner, &run_classifier(&1, opts))

    case runner.(build_input(issue, candidate_domains)) do
      {:ok, %{domain_ids: domain_ids}} ->
        persist_classification(issue, candidate_domains, domain_ids)

      {:ok, %{"domain_ids" => domain_ids}} ->
        persist_classification(issue, candidate_domains, domain_ids)

      {:ok, _other} ->
        {:error, :invalid_agent_response}

      {:error, :llm_not_configured} ->
        domain_ids = Enum.map(candidate_domains, & &1.id)
        persist!(issue, domain_ids)
        {:ok, domain_ids}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_classification(issue, candidate_domains, domain_ids) when is_list(domain_ids) do
    allowed = MapSet.new(candidate_domains, & &1.id)

    selected =
      domain_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.filter(&MapSet.member?(allowed, &1))

    persist!(issue, selected)
    {:ok, selected}
  end

  defp persist_classification(_issue, _candidate_domains, _other),
    do: {:error, :invalid_agent_response}

  defp persist!(%GitHubIssue{id: issue_id}, domain_ids) do
    classified_at = DateTime.utc_now() |> DateTime.truncate(:second)
    inserted_at = classified_at

    rows =
      Enum.map(domain_ids, fn domain_id ->
        %{
          forage_github_issue_id: issue_id,
          domain_id: domain_id,
          inserted_at: inserted_at,
          updated_at: inserted_at
        }
      end)

    Repo.transaction(fn ->
      from(link in GitHubIssueDomain, where: link.forage_github_issue_id == ^issue_id)
      |> Repo.delete_all()

      if rows != [], do: Repo.insert_all(GitHubIssueDomain, rows)

      GitHubIssue
      |> where([issue], issue.id == ^issue_id)
      |> Repo.update_all(
        set: [
          classified_at: classified_at,
          classification_failure: nil,
          classification_failed_at: nil
        ]
      )
    end)

    :ok
  end

  @doc """
  Records a terminal failure so scheduled sweeps do not repeat the model request.

  A reconsiderable failure (credit exhaustion, provider outage, transient
  retries exhausted) refreshes its own timestamp, which is what paces the
  sweeper's per-reason cooldown; a record-scoped failure is written once and
  left alone.
  """
  def mark_failed(issue_id, reason)
      when is_binary(issue_id) and (is_atom(reason) or is_binary(reason)) do
    failed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    reconsiderable = Errors.reconsiderable_reason_names()

    GitHubIssue
    |> where(
      [issue],
      issue.id == ^issue_id and is_nil(issue.classified_at) and
        (is_nil(issue.classification_failed_at) or
           issue.classification_failure in ^reconsiderable)
    )
    |> Repo.update_all(
      set: [classification_failure: to_string(reason), classification_failed_at: failed_at]
    )

    :ok
  end

  defp candidate_domains(repository_id) do
    case Repo.get(GitHubRepository, repository_id) do
      %GitHubRepository{project_id: project_id} when is_binary(project_id) ->
        Domain
        |> join(:inner, [domain], link in ProjectDomain,
          on: link.domain_id == domain.id and link.project_id == ^project_id
        )
        |> order_by([domain], asc: domain.name)
        |> Repo.all()

      _ ->
        []
    end
  end

  defp build_input(%GitHubIssue{} = issue, candidate_domains) do
    repository = issue.github_repository

    %{
      business_context: @business_context,
      candidate_domains:
        Enum.map(candidate_domains, fn domain ->
          %{
            id: domain.id,
            name: domain.name,
            description: truncate(domain.description || "", @max_domain_description_length)
          }
        end),
      issue: %{
        repository: "#{repository.owner}/#{repository.name}",
        number: issue.number,
        title: issue.title,
        body: truncate(issue.body, @max_body_length)
      }
    }
  end

  defp run_classifier(input, opts) do
    agent = Keyword.get(opts, :agent, GitHubIssueClassifierAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run_operation(agent, :classify_issue, input, agent_opts)
  end

  defp load_issue(id) do
    GitHubIssue
    |> preload(:github_repository)
    |> Repo.get(id)
  end

  defp agents_enabled?(opts) do
    fun = Keyword.get(opts, :agents_enabled?, &Agents.enabled?/0)
    fun.()
  end

  defp truncate(value, limit) when is_binary(value) and is_integer(limit) do
    if String.length(value) > limit,
      do: String.slice(value, 0, limit) <> "...",
      else: value
  end

  defp truncate(_value, _limit), do: ""
end
