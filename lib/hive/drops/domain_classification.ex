defmodule Hive.Drops.DomainClassification do
  @moduledoc """
  Resolves which domains a drop belongs to and persists the resulting
  links. Mirrors `Hive.Forage.GitHubIssueClassification`: when the LLM
  is configured the agent picks a subset of the candidate domains;
  otherwise every candidate domain is linked so the dashboard still
  has something to show.
  """

  import Ecto.Query

  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.Drops
  alias Hive.Drops.Agents.DomainClassifierAgent
  alias Hive.Drops.Drop
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
  alias Hive.Projects.ProjectDomain
  alias Hive.Repo

  @business_context """
  This organization tracks shipped updates across many product surfaces.
  Each domain is a durable business domain (a product, a sub-system, an
  operational area). A drop belongs to a domain when the update changes
  something users of that domain care about.
  """

  @max_body_length 500
  @max_domain_description_length 200

  @doc """
  Classifies the drop with `drop_id` and writes the resulting domain
  links. Returns `{:ok, [domain_id]}` on success, `{:error, :not_found}`
  for an unknown id, and `{:error, reason}` for an LLM error that should
  be retried by the caller.
  """
  def classify(drop_id, opts \\ []) when is_binary(drop_id) do
    case load_drop(drop_id) do
      nil -> {:error, :not_found}
      drop -> classify_drop(drop, opts)
    end
  end

  def classify_drop(%Drop{} = drop, opts \\ []) do
    candidates = candidate_domains(drop)

    cond do
      candidates == [] ->
        # No domains exist yet, or the GitHub release's repo isn't
        # connected to any domain. Leave classified_at nil so the
        # sweeper retries later.
        {:ok, []}

      not agents_enabled?(opts) ->
        ids = Enum.map(candidates, & &1.id)
        Drops.replace_drop_domains(drop, ids)
        {:ok, ids}

      true ->
        run_agent(drop, candidates, opts)
    end
  end

  defp run_agent(drop, candidates, opts) do
    input = build_input(drop, candidates)

    fingerprint = input_fingerprint(input)

    case reuse_classification(drop.id, fingerprint) do
      {:ok, :not_cached} ->
        run_and_persist(drop, candidates, input, fingerprint, opts)

      result ->
        result
    end
  end

  defp reuse_classification(drop_id, fingerprint) do
    Repo.transaction(fn ->
      current =
        Drop
        |> lock("FOR UPDATE")
        |> Repo.get!(drop_id)
        |> Repo.preload([:github_repository, :domains])

      if current.classification_fingerprint == fingerprint do
        current_input = build_input(current, candidate_domains(current))

        if input_fingerprint(current_input) != fingerprint do
          Repo.rollback(:classification_input_changed)
        end

        Drop
        |> where([drop], drop.id == ^drop_id)
        |> Repo.update_all(
          set: [
            classified_at: DateTime.utc_now() |> DateTime.truncate(:second),
            classification_failure: nil,
            classification_failed_at: nil
          ]
        )

        Enum.map(current.domains, & &1.id)
      else
        :not_cached
      end
    end)
  end

  defp run_and_persist(drop, candidates, input, fingerprint, opts) do
    runner = Keyword.get(opts, :runner, &run_classifier(&1, opts))

    case runner.(input) do
      {:ok, %{domain_ids: ids}} -> persist(drop, candidates, ids, fingerprint)
      {:ok, %{"domain_ids" => ids}} -> persist(drop, candidates, ids, fingerprint)
      {:ok, _other} -> {:error, :invalid_agent_response}
      {:error, :llm_not_configured} -> fallback(drop, candidates)
      {:error, reason} -> {:error, reason}
    end
  end

  defp fallback(drop, candidates) do
    ids = Enum.map(candidates, & &1.id)
    Drops.replace_drop_domains(drop, ids)
    {:ok, ids}
  end

  defp persist(drop, candidates, ids, fingerprint) when is_list(ids) do
    allowed = MapSet.new(candidates, & &1.id)

    selected =
      ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()
      |> Enum.filter(&MapSet.member?(allowed, &1))

    Repo.transaction(fn ->
      current =
        Drop |> lock("FOR UPDATE") |> Repo.get!(drop.id) |> Repo.preload(:github_repository)

      current_input = build_input(current, candidate_domains(current))

      if input_fingerprint(current_input) != fingerprint do
        Repo.rollback(:classification_input_changed)
      end

      Drops.replace_drop_domains(current, selected, classification_fingerprint: fingerprint)
    end)
  end

  defp persist(_drop, _candidates, _other, _fingerprint), do: {:error, :invalid_agent_response}

  defp candidate_domains(%Drop{
         source_type: :github_release,
         github_repository_id: repository_id
       })
       when is_binary(repository_id) do
    case Repo.get(GitHubRepository, repository_id) do
      %GitHubRepository{project_id: project_id} when is_binary(project_id) ->
        domains_for_project(project_id)

      _ ->
        []
    end
  end

  defp candidate_domains(%Drop{source_type: :rss, drop_source_id: source_id})
       when is_binary(source_id) do
    case Repo.get(Hive.Drops.DropSource, source_id) do
      %{project_id: project_id} when is_binary(project_id) ->
        domains_for_project(project_id)

      _ ->
        []
    end
  end

  defp candidate_domains(_drop) do
    Domain
    |> order_by([domain], asc: domain.name)
    |> Repo.all()
  end

  defp domains_for_project(project_id) do
    Domain
    |> join(:inner, [domain], link in ProjectDomain,
      on: link.domain_id == domain.id and link.project_id == ^project_id
    )
    |> order_by([domain], asc: domain.name)
    |> Repo.all()
  end

  defp build_input(%Drop{} = drop, candidates) do
    repository_label =
      case drop do
        %Drop{github_repository: %{owner: owner, name: name}} -> "#{owner}/#{name}"
        _ -> ""
      end

    %{
      business_context: @business_context,
      candidate_domains:
        Enum.map(candidates, fn domain ->
          %{
            id: domain.id,
            name: domain.name,
            description: truncate(domain.description || "", @max_domain_description_length)
          }
        end),
      drop: %{
        source_type: Atom.to_string(drop.source_type),
        repository: repository_label,
        version: drop.version || "",
        title: drop.title || "",
        body: truncate(drop.body, @max_body_length)
      }
    }
  end

  defp input_fingerprint(input) do
    :crypto.hash(:sha256, :erlang.term_to_binary(input, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp run_classifier(input, opts) do
    agent = Keyword.get(opts, :agent, DomainClassifierAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run_object_operation(agent, :classify_drop, input, agent_opts)
  end

  defp load_drop(id) do
    Drop
    |> preload(:github_repository)
    |> Repo.get(id)
  end

  defp agents_enabled?(opts) do
    fun = Keyword.get(opts, :agents_enabled?, &Agents.enabled?/0)
    fun.()
  end

  defp truncate(nil, _limit), do: ""

  defp truncate(value, limit) when is_binary(value) and is_integer(limit) do
    if String.length(value) > limit,
      do: String.slice(value, 0, limit) <> "...",
      else: value
  end

  defp truncate(_value, _limit), do: ""
end
