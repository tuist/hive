defmodule Hive.Domains.Evolution do
  @moduledoc """
  Builds the domain evolution input and applies agent-proposed changes.
  """

  import Ecto.Query

  alias Hive.Agents.Errors
  alias Hive.Agents.Sessions
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GrafanaAlert
  alias Hive.Domains
  alias Hive.Domains.Agents.EvolutionAgent
  alias Hive.Domains.Domain
  alias Hive.Domains.EvolutionEvaluation
  alias Hive.Projects.Project
  alias Hive.Repo
  alias Hive.Specs.Spec

  @default_limit 40
  @max_body_length 1_200

  @business_context """
  Tuist builds infrastructure for productive software development, including
  caching, compute environments, and support for build systems such as Xcode,
  Gradle, and Bazel. Important domains include build automation, remote caching,
  testing, CI, release workflows, developer experience, documentation, Atlas
  operations, Hive product planning, forage, specs, MCP, identity, and Once
  distribution.
  """

  @generic_names MapSet.new(
                   ~w(backlog bugs core feedback features infrastructure operations platform product products roadmap work workstream)
                 )

  @business_terms ~w(
    account alert alerts app apple apps auth authentication authorization automation bazel build builds cache caching ci cli
    command commands compute developer developers development design docs documentation environment environments forage github gradle grafana hive identity
    interface ios macos mcp once onboarding operations organization organizations package packages project projects
    release releases repository repositories spec specs swift system test testing tests tuist workflow workflows xcode
  )

  def evolve_from_work_items(opts \\ []) do
    input = build_input(opts)
    fingerprint = input_fingerprint(input)

    cond do
      input.work_items == [] ->
        {:ok, empty_result()}

      skip_fingerprint?(fingerprint) ->
        {:ok, empty_result()}

      true ->
        runner = Keyword.get(opts, :runner, &run_agent(&1, opts))
        run_and_record(runner, input, fingerprint)
    end
  end

  defp run_and_record(runner, input, fingerprint) do
    case runner.(input) do
      {:ok, plan} ->
        record_successful_run(fingerprint, input, plan)

      {:error, :llm_not_configured} = error ->
        error

      {:error, reason} ->
        record_failed_evaluation(fingerprint, input, reason)
        {:error, Errors.sanitize_reason(reason, :domain_evolution_failed)}
    end
  end

  defp record_successful_run(fingerprint, input, plan) do
    with {:ok, result} <- apply_plan(plan),
         {:ok, _evaluation} <- record_evaluation(fingerprint, input, result) do
      {:ok, result}
    end
  end

  def build_input(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    %{
      business_context: @business_context,
      current_projects: current_projects(),
      current_domains: current_domains(),
      work_items: work_items(limit)
    }
  end

  def apply_plan(plan) do
    result =
      plan
      |> plan_changes()
      |> Enum.reduce(empty_result(), fn change, acc ->
        case apply_change(change) do
          {:created, domain} ->
            %{acc | created: [domain | acc.created]}

          {:updated, domain} ->
            %{acc | updated: [domain | acc.updated]}

          {:skipped, reason} ->
            %{acc | skipped: [%{change: change, reason: reason} | acc.skipped]}
        end
      end)
      |> reverse_result()

    {:ok, result}
  end

  defp run_agent(input, opts) do
    agent = Keyword.get(opts, :agent, EvolutionAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run_operation(agent, :evolve_domains, input, agent_opts)
  end

  defp skip_fingerprint?(fingerprint) do
    case Repo.get_by(EvolutionEvaluation, fingerprint: fingerprint) do
      nil ->
        false

      %EvolutionEvaluation{outcome: outcome} when outcome in [:changed, :noop] ->
        true

      %EvolutionEvaluation{outcome: :failed, reason: reason, evaluated_at: evaluated_at} ->
        within_reason_cooldown?(reason, evaluated_at)
    end
  end

  defp within_reason_cooldown?(nil, _evaluated_at), do: true

  defp within_reason_cooldown?(reason, evaluated_at) do
    case Errors.reconsideration_cooldown(reason) do
      nil ->
        # Non-reconsiderable failure: skip until the input fingerprint changes.
        true

      cooldown ->
        cutoff = DateTime.utc_now() |> DateTime.add(-cooldown, :second)
        DateTime.compare(evaluated_at, cutoff) != :lt
    end
  end

  defp record_evaluation(fingerprint, input, result) do
    changed? = result.created != [] or result.updated != []

    upsert_evaluation(fingerprint, %{
      fingerprint: fingerprint,
      outcome: if(changed?, do: :changed, else: :noop),
      reason: nil,
      work_items_count: length(input.work_items),
      created_count: length(result.created),
      updated_count: length(result.updated),
      skipped_count: length(result.skipped),
      evaluated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp record_failed_evaluation(fingerprint, input, reason) do
    hard_reason = Errors.hard_failure_reason(reason)
    unavailable? = Errors.provider_unavailable?(reason)

    stored_reason =
      cond do
        hard_reason -> hard_reason
        unavailable? -> :llm_provider_unavailable
        true -> :agent_failed
      end

    upsert_evaluation(fingerprint, %{
      fingerprint: fingerprint,
      outcome: :failed,
      reason: to_string(stored_reason),
      work_items_count: length(input.work_items),
      created_count: 0,
      updated_count: 0,
      skipped_count: 0,
      evaluated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp upsert_evaluation(fingerprint, attrs) do
    case Repo.get_by(EvolutionEvaluation, fingerprint: fingerprint) do
      nil ->
        %EvolutionEvaluation{}
        |> EvolutionEvaluation.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> EvolutionEvaluation.changeset(attrs)
        |> Repo.update()
    end
  end

  defp input_fingerprint(input) do
    input
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp current_domains do
    Domain
    |> order_by([domain], asc: domain.name)
    |> preload(:projects)
    |> Repo.all()
    |> Enum.map(fn domain ->
      %{
        id: domain.id,
        name: domain.name,
        description: domain.description || "",
        visibility: Atom.to_string(domain.visibility),
        projects: project_refs(domain.projects)
      }
    end)
  end

  defp current_projects do
    Project
    |> order_by([project], asc: project.name)
    |> Repo.all()
    |> project_refs()
  end

  defp work_items(limit) do
    limit
    |> feature_request_items()
    |> Kernel.++(github_issue_items(limit))
    |> Kernel.++(grafana_alert_items(limit))
    |> Kernel.++(spec_items(limit))
    |> Enum.sort(fn left, right -> newer_or_equal?(left.sort_at, right.sort_at) end)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :sort_at))
  end

  defp feature_request_items(limit) do
    FeatureRequest
    |> where([request], request.status != :closed)
    |> order_by([request], desc: request.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn request ->
      %{
        id: request.id,
        kind: "feature_request",
        title: request.title,
        body: truncate(request.description),
        status: Atom.to_string(request.status),
        source: "forage_feature_requests",
        domains: [],
        projects: [],
        occurred_at: iso8601(request.inserted_at),
        sort_at: request.inserted_at
      }
    end)
  end

  defp github_issue_items(limit) do
    GitHubIssue
    |> where([issue], issue.state == :open)
    |> order_by([issue], desc: issue.updated_at)
    |> limit(^limit)
    |> preload([:domains, github_repository: :project])
    |> Repo.all()
    |> Enum.map(fn issue ->
      repository = issue.github_repository
      source = "#{repository.owner}/#{repository.name}##{issue.number}"

      %{
        id: issue.id,
        kind: "github_issue",
        title: issue.title,
        body: truncate(issue.body || ""),
        status: Atom.to_string(issue.state),
        source: source,
        domains: Enum.map(issue.domains, & &1.name),
        projects: project_refs([repository.project]),
        occurred_at: iso8601(issue.updated_at),
        sort_at: issue.updated_at
      }
    end)
  end

  defp grafana_alert_items(limit) do
    GrafanaAlert
    |> order_by([alert], desc: alert.last_received_at)
    |> limit(^limit)
    |> preload([:domain, :project])
    |> Repo.all()
    |> Enum.map(fn alert ->
      %{
        id: alert.id,
        kind: "grafana_alert",
        title: alert.title,
        body: truncate(alert.summary || labels_summary(alert.labels)),
        status: Atom.to_string(alert.status),
        source: "grafana",
        domains: domain_names([alert.domain]),
        projects: project_refs([alert.project]),
        occurred_at: iso8601(alert.last_received_at),
        sort_at: alert.last_received_at || alert.updated_at
      }
    end)
  end

  defp spec_items(limit) do
    Spec
    |> where([spec], spec.status not in [:archived, :rejected])
    |> order_by([spec], desc: spec.updated_at)
    |> limit(^limit)
    |> preload([:project, domains: :projects])
    |> Repo.all()
    |> Enum.map(fn spec ->
      %{
        id: spec.id,
        kind: "spec",
        title: spec.title,
        body: truncate(spec.summary || spec.body),
        status: Atom.to_string(spec.status),
        source: "specs",
        domains: Enum.map(spec.domains, & &1.name),
        projects: project_refs([spec.project]),
        occurred_at: iso8601(spec.updated_at),
        sort_at: spec.updated_at
      }
    end)
  end

  defp labels_summary(labels) when is_map(labels) do
    Enum.map_join(labels, ", ", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp labels_summary(_labels), do: ""

  defp project_refs(projects) do
    projects
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn project -> %{id: project.id, name: project.name} end)
  end

  defp domain_names(domains) do
    domains
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.name)
  end

  defp apply_change(change) do
    action = change |> value(:action) |> normalize_action()
    name = change |> value(:name) |> normalize_text()
    description = change |> value(:description) |> normalize_text()
    project_ids = change |> value(:project_ids) |> normalize_project_ids()

    cond do
      action not in ["create", "update"] ->
        {:skipped, :invalid_action}

      name == "" or description == "" ->
        {:skipped, :missing_required_fields}

      not acceptable_name?(name) ->
        {:skipped, :unfit_domain_name}

      not business_aligned?(name, description) ->
        {:skipped, :outside_tuist_business_domain}

      action == "create" ->
        create_domain(name, description, project_ids)

      action == "update" ->
        change
        |> value(:domain_id)
        |> update_domain(name, description)
    end
  end

  defp create_domain(name, description, requested_project_ids) do
    case domain_by_normalized_name(name) do
      %Domain{} ->
        {:skipped, :duplicate_domain_name}

      nil ->
        case target_project_ids(requested_project_ids) do
          {:ok, project_ids} -> insert_domain(name, description, project_ids)
          {:error, reason} -> {:skipped, reason}
        end
    end
  end

  defp insert_domain(name, description, [project_id | remaining_project_ids]) do
    case Domains.create_domain(%{
           name: name,
           description: description,
           project_id: project_id
         }) do
      {:ok, domain} ->
        Enum.each(remaining_project_ids, &Domains.link_domain_to_project(domain, &1))

        {:created, Domains.get_domain!(domain.id)}

      {:error, changeset} ->
        {:skipped, {:invalid_domain, changeset_errors(changeset)}}
    end
  end

  defp target_project_ids([]), do: fallback_project_ids()

  defp target_project_ids(requested_project_ids) do
    with {:ok, project_ids} <- cast_project_ids(requested_project_ids),
         :ok <- ensure_projects_exist(project_ids) do
      {:ok, project_ids}
    end
  end

  defp fallback_project_ids do
    case Repo.get_by(Project, name: "Tuist") do
      %Project{id: id} ->
        {:ok, [id]}

      nil ->
        Project
        |> order_by([project], asc: project.name)
        |> select([project], project.id)
        |> Repo.all()
        |> case do
          [id] -> {:ok, [id]}
          [] -> {:error, :missing_project}
          _ids -> {:error, :missing_project_ids}
        end
    end
  end

  defp cast_project_ids(project_ids) do
    Enum.reduce_while(project_ids, {:ok, []}, fn project_id, {:ok, acc} ->
      case Ecto.UUID.cast(project_id) do
        {:ok, uuid} -> {:cont, {:ok, [uuid | acc]}}
        :error -> {:halt, {:error, :invalid_project_id}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, Enum.reverse(ids)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_projects_exist(project_ids) do
    found_ids =
      Project
      |> where([project], project.id in ^project_ids)
      |> select([project], project.id)
      |> Repo.all()
      |> MapSet.new()

    if Enum.all?(project_ids, &MapSet.member?(found_ids, &1)) do
      :ok
    else
      {:error, :unknown_project_id}
    end
  end

  defp update_domain(nil, _name, _description), do: {:skipped, :missing_domain_id}
  defp update_domain("", _name, _description), do: {:skipped, :missing_domain_id}

  defp update_domain(domain_id, name, description) do
    with {:ok, domain} <- fetch_domain(domain_id),
         :ok <- validate_unique_update_name(domain, name) do
      case Domains.update_domain(domain, %{name: name, description: description}) do
        {:ok, domain} -> {:updated, domain}
        {:error, changeset} -> {:skipped, {:invalid_domain, changeset_errors(changeset)}}
      end
    else
      {:error, reason} -> {:skipped, reason}
    end
  end

  defp fetch_domain(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Domain{} = domain <- Repo.get(Domain, uuid) do
      {:ok, domain}
    else
      :error -> {:error, :invalid_domain_id}
      nil -> {:error, :unknown_domain_id}
    end
  end

  defp validate_unique_update_name(%Domain{id: domain_id}, name) do
    case domain_by_normalized_name(name) do
      nil -> :ok
      %Domain{id: ^domain_id} -> :ok
      %Domain{} -> {:error, :duplicate_domain_name}
    end
  end

  defp domain_by_normalized_name(name) do
    normalized_name = normalize_name(name)

    Domain
    |> Repo.all()
    |> Enum.find(&(normalize_name(&1.name) == normalized_name))
  end

  defp acceptable_name?(name) do
    normalized = normalize_name(name)
    words = String.split(name, ~r/\s+/, trim: true)

    normalized not in @generic_names and
      length(words) <= 5 and
      not String.match?(name, ~r/(#\d+|\b\d{3,}\b|\/|https?:|`|\.swift)/i)
  end

  defp business_aligned?(name, description) do
    haystack = String.downcase("#{name} #{description}")
    Enum.any?(@business_terms, &String.contains?(haystack, &1))
  end

  defp plan_changes(%{changes: changes}) when is_list(changes), do: changes
  defp plan_changes(%{"changes" => changes}) when is_list(changes), do: changes
  defp plan_changes(_plan), do: []

  defp value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value(_map, _key), do: nil

  defp normalize_action(action) when is_atom(action), do: Atom.to_string(action)

  defp normalize_action(action) when is_binary(action),
    do: action |> String.trim() |> String.downcase()

  defp normalize_action(_action), do: nil

  defp normalize_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_text(_value), do: ""

  defp normalize_name(name), do: name |> normalize_text() |> String.downcase()

  defp normalize_project_ids(project_ids) when is_list(project_ids) do
    project_ids
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_project_ids(_project_ids), do: []

  defp truncate(value) when is_binary(value) do
    if String.length(value) > @max_body_length,
      do: String.slice(value, 0, @max_body_length) <> "...",
      else: value
  end

  defp truncate(_value), do: ""

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(_datetime), do: ""

  defp newer_or_equal?(nil, _right), do: false
  defp newer_or_equal?(_left, nil), do: true
  defp newer_or_equal?(left, right), do: DateTime.compare(left, right) != :lt

  defp empty_result, do: %{created: [], updated: [], skipped: []}

  defp reverse_result(result) do
    %{
      created: Enum.reverse(result.created),
      updated: Enum.reverse(result.updated),
      skipped: Enum.reverse(result.skipped)
    }
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
