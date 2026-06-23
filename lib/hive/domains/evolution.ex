defmodule Hive.Domains.Evolution do
  @moduledoc """
  Builds the domain evolution input and applies agent-proposed changes.
  """

  import Ecto.Query

  alias Hive.Agents.Sessions
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GrafanaAlert
  alias Hive.Domains
  alias Hive.Domains.Agents.EvolutionAgent
  alias Hive.Domains.Domain
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

    if input.work_items == [] do
      {:ok, empty_result()}
    else
      runner = Keyword.get(opts, :runner, &run_agent(&1, opts))

      with {:ok, plan} <- runner.(input) do
        apply_plan(plan)
      end
    end
  end

  def build_input(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    %{
      business_context: @business_context,
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

  defp current_domains do
    Domain
    |> order_by([domain], asc: domain.name)
    |> Repo.all()
    |> Enum.map(fn domain ->
      %{
        id: domain.id,
        name: domain.name,
        description: domain.description || "",
        visibility: Atom.to_string(domain.visibility)
      }
    end)
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
    |> preload([:github_repository, :domains])
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
        occurred_at: iso8601(issue.updated_at),
        sort_at: issue.updated_at
      }
    end)
  end

  defp grafana_alert_items(limit) do
    GrafanaAlert
    |> order_by([alert], desc: alert.last_received_at)
    |> limit(^limit)
    |> preload(:domain)
    |> Repo.all()
    |> Enum.map(fn alert ->
      %{
        id: alert.id,
        kind: "grafana_alert",
        title: alert.title,
        body: truncate(alert.summary || labels_summary(alert.labels)),
        status: Atom.to_string(alert.status),
        source: "grafana",
        domains: [alert.domain.name],
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
    |> preload(:domains)
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
        occurred_at: iso8601(spec.updated_at),
        sort_at: spec.updated_at
      }
    end)
  end

  defp labels_summary(labels) when is_map(labels) do
    Enum.map_join(labels, ", ", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp labels_summary(_labels), do: ""

  defp apply_change(change) do
    action = change |> value(:action) |> normalize_action()
    name = change |> value(:name) |> normalize_text()
    description = change |> value(:description) |> normalize_text()

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
        create_domain(name, description)

      action == "update" ->
        change
        |> value(:domain_id)
        |> update_domain(name, description)
    end
  end

  defp create_domain(name, description) do
    case domain_by_normalized_name(name) do
      %Domain{} ->
        {:skipped, :duplicate_domain_name}

      nil ->
        with {:ok, project_id} <- evolution_project_id() do
          case Domains.create_domain(%{
                 name: name,
                 description: description,
                 project_id: project_id
               }) do
            {:ok, domain} -> {:created, domain}
            {:error, changeset} -> {:skipped, {:invalid_domain, changeset_errors(changeset)}}
          end
        else
          {:error, reason} -> {:skipped, reason}
        end
    end
  end

  defp evolution_project_id do
    case Repo.get_by(Project, name: "Tuist") do
      %Project{id: id} -> {:ok, id}
      nil -> {:error, :missing_tuist_project}
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
