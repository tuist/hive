defmodule Hive.Forage.CodingRuns do
  @moduledoc """
  Durable agent executions for Forage items.

  A Flight snapshots its Forage item, objective, trigger, and repository,
  executes the matching agent in the configured sandbox, and persists either
  a pull request or a report result.
  """

  import Ecto.Query

  require Logger

  alias Condukt.Sandbox
  alias Hive.Accounts.User
  alias Hive.Agents.Errors
  alias Hive.Agents.Sessions
  alias Hive.Audit
  alias Hive.Domains.GitHubRepository
  alias Hive.Flights.Flight
  alias Hive.Flights.Policy
  alias Hive.Forage.Agents.GrafanaAlertCodingAgent
  alias Hive.Forage.Agents.InvestigationAgent
  alias Hive.Forage.Agents.ReproductionAgent
  alias Hive.Forage.CodingRunWorker
  alias Hive.Forage.CodingRuns.SandboxContract
  alias Hive.Forage.CodingRuns.Workspace
  alias Hive.Forage.Item
  alias Hive.Forage.GrafanaAlert
  alias Hive.GitHub.Client
  alias Hive.GitHub.CodeChanges
  alias Hive.GitHub.Issues
  alias Hive.Repo

  @topic_prefix "forage:coding_runs:"
  @default_timeout_minutes 30
  @max_prompt_field_characters 4_000

  def config(conf \\ Application.get_env(:hive, :coding_runs, [])) do
    %{
      runner: normalize_runner(Keyword.get(conf, :runner, :disabled)),
      image: Keyword.get(conf, :image, "ubuntu:24.04"),
      cpus: Keyword.get(conf, :cpus, 2),
      memory: Keyword.get(conf, :memory, 4096),
      disk: Keyword.get(conf, :disk, 8192),
      timeout_minutes: Keyword.get(conf, :timeout_minutes, @default_timeout_minutes),
      setup_command: Keyword.get(conf, :setup_command) || Workspace.default_setup_command(),
      sandbox_module: Keyword.get(conf, :sandbox_module),
      sandbox_options: normalize_sandbox_options(Keyword.get(conf, :sandbox_options, %{})),
      microsandbox_home: Keyword.get(conf, :microsandbox_home)
    }
  end

  def enabled?(conf \\ Application.get_env(:hive, :coding_runs, [])) do
    configured = config(conf)

    Hive.Agents.coding_enabled?() and Client.configured?() and
      SandboxContract.configured?(configured)
  end

  def subscribe(forage_item_id) when is_binary(forage_item_id) do
    Phoenix.PubSub.subscribe(Hive.PubSub, topic(forage_item_id))
  end

  def list_for_item(forage_item_id) when is_binary(forage_item_id) do
    Flight
    |> where([run], run.forage_item_id == ^forage_item_id)
    |> order_by([run], desc: run.inserted_at)
    |> preload([:repository, :requested_by])
    |> Repo.all()
  end

  def get(id) when is_binary(id) do
    Flight
    |> preload([:repository, :requested_by])
    |> Repo.get(id)
  rescue
    Ecto.Query.CastError -> nil
  end

  def get_for_user(id, user) do
    if Policy.authorize?(:flight_read, user, nil), do: get(id), else: nil
  end

  def repositories_for_item(%Item{origin: :grafana, source_record: alert}) do
    case alert.project do
      %{github_repositories: repositories} when is_list(repositories) -> repositories
      _other -> []
    end
  end

  def repositories_for_item(%Item{origin: :github, repository_id: repository_id})
      when is_binary(repository_id) do
    case Repo.get(GitHubRepository, repository_id) do
      nil -> []
      repository -> [repository]
    end
  end

  def repositories_for_item(_item), do: []

  def active_for_item_repository(forage_item_id, repository_id)
      when is_binary(forage_item_id) and is_binary(repository_id) do
    Flight
    |> where([flight], flight.forage_item_id == ^forage_item_id)
    |> where([flight], flight.repository_id == ^repository_id)
    |> where([flight], flight.status in [:queued, :running])
    |> order_by([flight], desc: flight.inserted_at)
    |> preload([:repository, :requested_by])
    |> Repo.one()
  end

  def create_for_item(item, repository_id, user, opts \\ [])

  def create_for_item(%Item{} = item, repository_id, %User{} = user, opts)
      when is_binary(repository_id) do
    enabled? = Keyword.get(opts, :enabled?, &enabled?/0)

    cond do
      not Policy.authorize?(:flight_create, user, item) ->
        {:error, :unauthorized}

      not enabled?.() ->
        {:error, :not_configured}

      true ->
        create_for_repository(item, repository_id, user, opts)
    end
  end

  def create_for_item(_item, _repository_id, _user, _opts), do: {:error, :unauthorized}

  def create_for_grafana_alert(alert, repository_id, user, opts \\ [])

  def create_for_grafana_alert(%GrafanaAlert{} = alert, repository_id, %User{} = user, opts)
      when is_binary(repository_id) do
    with {:ok, item} <- Hive.Forage.get_item_for_user("grafana_alert:#{alert.id}", user) do
      create_for_item(item, repository_id, user, Keyword.put_new(opts, :objective, :fix))
    end
  end

  def create_for_grafana_alert(_alert, _repository_id, _user, _opts),
    do: {:error, :unauthorized}

  def execute(coding_run_id, opts \\ []) when is_binary(coding_run_id) do
    case get(coding_run_id) do
      nil ->
        :ok

      %Flight{status: status} when status in [:running, :succeeded, :failed] ->
        :ok

      %Flight{} = run ->
        Audit.put_context(%{interface: "worker", actor_kind: "system", actor_name: "Flight"})

        case claim_run(run) do
          {:ok, claimed_run} -> do_execute(claimed_run, opts)
          :already_claimed -> :ok
        end
    end
  rescue
    error ->
      fail_run(coding_run_id, error)
  catch
    kind, reason ->
      fail_run(coding_run_id, {kind, reason})
  end

  def status_label(:queued), do: "Queued"
  def status_label(:running), do: "Running"
  def status_label(:succeeded), do: "Succeeded"
  def status_label(:failed), do: "Failed"

  def status_color(:queued), do: "neutral"
  def status_color(:running), do: "information"
  def status_color(:succeeded), do: "success"
  def status_color(:failed), do: "destructive"

  defp create_for_repository(item, repository_id, user, opts) do
    repository = Enum.find(repositories_for_item(item), &(&1.id == repository_id))

    case repository do
      nil ->
        {:error, :repository_not_found}

      repository ->
        insert_run(item, repository, user, opts)
    end
  end

  defp insert_run(item, repository, user, opts) do
    runner =
      opts |> Keyword.get(:config, Application.get_env(:hive, :coding_runs, [])) |> config()

    objective = normalize_objective(Keyword.get(opts, :objective, :investigate))

    attrs = %{
      forage_item_id: item.id,
      status: :queued,
      objective: objective,
      runner: runner.runner,
      repository_full_name: GitHubRepository.full_name(repository),
      repository_id: repository.id,
      requested_by_id: user.id,
      parent_flight_id: Keyword.get(opts, :parent_flight_id),
      trigger: Keyword.get(opts, :trigger, %{}),
      input: item_input(item, repository)
    }

    result =
      Repo.transaction(fn ->
        with {:ok, run} <- %Flight{} |> Flight.changeset(attrs) |> Repo.insert(),
             {:ok, _job} <-
               %{"coding_run_id" => run.id}
               |> CodingRunWorker.new()
               |> Oban.insert() do
          run
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, run} ->
        Audit.record("flight.created", %{
          target_type: "flight",
          target_id: run.id,
          target_label: item.title,
          metadata: %{
            "forage_item_id" => run.forage_item_id,
            "objective" => Atom.to_string(run.objective),
            "repository" => run.repository_full_name,
            "runner" => run.runner
          }
        })

        broadcast(run)
        notify_slack(run)
        {:ok, Repo.preload(run, [:repository, :requested_by])}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Keyword.has_key?(errors, :forage_item_id),
          do: {:error, :already_running},
          else: {:error, :invalid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_execute(run, opts) do
    source_module = Keyword.get(opts, :source_module, CodeChanges)
    sessions_module = Keyword.get(opts, :sessions_module, Sessions)
    conf = config(Keyword.get(opts, :config, Application.get_env(:hive, :coding_runs, [])))

    with {:ok, source} <- source_module.fetch_source(run.repository, opts),
         {:ok, sandbox} <- build_sandbox(run, source, conf, opts) do
      case execute_in_sandbox(run, sandbox, sessions_module, conf, source) do
        {:ok, {agent_result, changes, session}} ->
          finish_execution(run, source, changes, agent_result, session, source_module, opts)

        {:error, reason, session} ->
          mark_failed(run.id, reason, session)

        {:error, reason} ->
          mark_failed(run.id, reason)
      end
    else
      {:error, reason} -> mark_failed(run.id, reason)
    end
  end

  defp finish_execution(run, source, changes, agent_result, session, source_module, opts) do
    case finish_result(run, source, changes, agent_result, source_module, opts) do
      {:ok, result} -> succeed_run(run.id, result, session)
      {:error, reason} -> mark_failed(run.id, reason, session)
    end
  end

  defp execute_in_sandbox(run, sandbox, sessions_module, conf, source) do
    try do
      maybe_store_runner_id(run, sandbox)
      agent = agent_for(run.objective)

      with {:ok, %{result: agent_result, session: session}} <-
             sessions_module.run_with_session(
               agent,
               prompt(run),
               inference_role: :coding,
               id: run.id,
               sandbox: sandbox,
               cwd: Sandbox.cwd(sandbox),
               load_project_instructions: true,
               output: agent.output_schema(),
               max_turns: 80,
               timeout: :timer.minutes(conf.timeout_minutes)
             ),
           {:ok, changes} <- Workspace.collect_changes(sandbox) do
        {:ok, {agent_result, changes, continuation_session(run, source, session)}}
      else
        {:error, reason, session} ->
          {:error, reason, continuation_session(run, source, session)}

        {:error, reason} ->
          {:error, reason}
      end
    after
      Sandbox.shutdown(sandbox)
    end
  end

  defp build_sandbox(run, source, conf, opts) do
    common = [
      source_archive: source.archive,
      base_branch: source.base_branch,
      runner: run.runner,
      image: conf.image,
      cpus: conf.cpus,
      memory: conf.memory,
      disk: conf.disk,
      timeout_minutes: conf.timeout_minutes,
      setup_command: conf.setup_command,
      provider_options: conf.sandbox_options,
      msb_home: conf.microsandbox_home,
      id: run.id
    ]

    case Keyword.get(opts, :sandbox_builder) do
      builder when is_function(builder, 1) -> builder.(common)
      nil -> SandboxContract.new(run, source, conf, opts)
    end
  end

  defp finish_result(
         %Flight{objective: :fix} = run,
         source,
         [_change | _rest] = changes,
         agent_result,
         source_module,
         opts
       ) do
    attrs = publication_attrs(run, changes, agent_result)

    case source_module.publish(run.repository, source, changes, attrs, opts) do
      {:ok, pull_request} ->
        {:ok,
         %{
           "type" => "pull_request",
           "objective_outcome" => "fixed",
           "number" => pull_request.number,
           "title" => pull_request.title,
           "url" => pull_request.url,
           "branch" => attrs.branch,
           "base_branch" => source.base_branch,
           "base_revision" => source.base_sha,
           "repository" => run.repository_full_name,
           "summary" => result_value(agent_result, :summary),
           "validation" => result_value(agent_result, :validation, [])
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finish_result(run, source, _changes, agent_result, _source_module, opts) do
    result = report_result(run, source, agent_result)

    case publish_report_to_source(run, result, opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Flight #{run.id} produced a report but publishing it to the source failed: #{inspect(reason)}"
        )
    end

    {:ok, result}
  end

  defp report_result(run, source, agent_result) do
    raw_outcome = result_value(agent_result, :outcome, "inconclusive")
    objective_outcome = objective_outcome(run.objective, raw_outcome)

    %{
      "type" => "report",
      "repository" => run.repository_full_name,
      "outcome" => raw_outcome,
      "objective_outcome" => Atom.to_string(objective_outcome),
      "base_branch" => source.base_branch,
      "base_revision" => source.base_sha,
      "summary" => result_value(agent_result, :summary),
      "root_cause" => result_value(agent_result, :root_cause),
      "validation" => result_value(agent_result, :validation, [])
    }
  end

  defp publication_attrs(run, changes, agent_result) do
    title = "fix(forage): address #{String.slice(run.input["title"] || "Forage item", 0, 72)}"

    %{
      branch: "hive/flight-#{String.slice(run.id, 0, 8)}",
      commit_message: title,
      title: title,
      body: pull_request_body(run, changes, agent_result)
    }
  end

  defp pull_request_body(run, changes, agent_result) do
    changed_paths = Enum.map_join(changes, "\n", &"- `#{&1.path}`")
    validation = result_value(agent_result, :validation, [])

    validation =
      if validation == [], do: "- Not run", else: Enum.map_join(validation, "\n", &"- `#{&1}`")

    """
    ## What changed

    #{result_value(agent_result, :summary)}

    #{changed_paths}

    ## Why

    This change was prepared from the Forage item **#{run.input["title"]}** in Hive.

    ## Root cause

    #{result_value(agent_result, :root_cause)}

    ## Approach

    Hive ran its coding harness against an isolated snapshot of `#{run.repository_full_name}` and published the returned file changes through the GitHub App.

    ## Impact

    The change is limited to the item's linked repository and is ready for normal review.

    ## Validation

    #{validation}
    """
  end

  defp prompt(run) do
    labels = run.input["labels"] |> then(&JSON.encode!(&1 || %{})) |> prompt_field()

    """
    #{objective_instruction(run.objective)}

    Title: #{prompt_field(run.input["title"])}
    Details: #{prompt_field(run.input["body"] || "No details were provided.")}
    Status: #{run.input["status"]}
    Source: #{prompt_field(run.input["source"])}
    Repository: #{run.repository_full_name}
    Labels: #{labels}

    Return the required structured result with concrete evidence and validation.
    """
  end

  defp item_input(%Item{} = item, repository) do
    base = %{
      "kind" => Atom.to_string(item.type),
      "forage_item_id" => item.id,
      "title" => item.title,
      "body" => item.body,
      "status" => Atom.to_string(item.status),
      "source" => item.source_label,
      "source_url" => item.external_url,
      "repository" => GitHubRepository.full_name(repository)
    }

    case item do
      %Item{origin: :grafana, source_record: alert} ->
        project = if Ecto.assoc_loaded?(alert.project), do: alert.project, else: nil

        Map.merge(base, %{
          "alert_id" => alert.id,
          "labels" => alert.labels,
          "generator_url" => alert.generator_url,
          "project" => project && project.name,
          "project_id" => alert.project_id
        })

      %Item{origin: :github, source_record: issue} ->
        Map.merge(base, %{
          "github_issue_id" => issue.id,
          "issue_number" => issue.number
        })

      _item ->
        base
    end
  end

  defp claim_run(run) do
    now = now()

    query =
      from(candidate in Flight, where: candidate.id == ^run.id and candidate.status == :queued)

    case Repo.update_all(query,
           set: [status: :running, started_at: now, error: nil, updated_at: now]
         ) do
      {1, _rows} ->
        claimed_run = get(run.id)
        broadcast(claimed_run)
        notify_slack(claimed_run)
        {:ok, claimed_run}

      {0, _rows} ->
        :already_claimed
    end
  end

  defp maybe_store_runner_id(run, sandbox) do
    runner_id = SandboxContract.runner_id(sandbox)

    if runner_id do
      run
      |> Flight.changeset(%{runner_id: runner_id})
      |> Repo.update!()
    end

    :ok
  end

  defp succeed_run(id, result, session) do
    run = Repo.get!(Flight, id)

    run =
      run
      |> Flight.changeset(%{
        status: :succeeded,
        objective_outcome: result["objective_outcome"],
        result: result,
        session: session,
        completed_at: now(),
        error: nil
      })
      |> Repo.update!()

    Audit.record(
      "flight.completed",
      audit_attrs(run, %{"result_type" => result["type"]})
    )

    broadcast(run)
    notify_slack(run)
    :ok
  end

  defp mark_failed(id, reason, session \\ nil) do
    case Repo.get(Flight, id) do
      nil ->
        :ok

      %Flight{status: status} when status in [:succeeded, :failed] ->
        :ok

      run ->
        error = format_error(reason)

        run =
          run
          |> Flight.changeset(%{
            status: :failed,
            error: error,
            session: session || run.session,
            completed_at: now()
          })
          |> Repo.update!()

        Audit.record("flight.failed", audit_attrs(run, %{"error" => error}))
        broadcast(run)
        notify_slack(run)
        :ok
    end
  end

  defp fail_run(id, reason) do
    mark_failed(id, reason)
    :ok
  end

  defp audit_attrs(run, metadata) do
    %{
      target_type: "flight",
      target_id: run.id,
      target_label: run.input["title"],
      metadata:
        Map.merge(metadata, %{
          "forage_item_id" => run.forage_item_id,
          "objective" => Atom.to_string(run.objective),
          "repository" => run.repository_full_name,
          "runner" => run.runner
        })
    }
  end

  defp broadcast(run) do
    Phoenix.PubSub.broadcast(
      Hive.PubSub,
      topic(run.forage_item_id),
      {:coding_run_updated, run.id}
    )
  end

  defp result_value(result, key, default \\ "") do
    Map.get(result, key) || Map.get(result, Atom.to_string(key)) || default
  end

  defp continuation_session(run, source, session) do
    Map.merge(session || %{}, %{
      "source" => %{
        "repository" => run.repository_full_name,
        "base_branch" => source.base_branch,
        "base_revision" => source.base_sha
      }
    })
  end

  defp prompt_field(nil), do: "Unknown"

  defp prompt_field(value),
    do: value |> to_string() |> String.slice(0, @max_prompt_field_characters)

  defp agent_for(:investigate), do: InvestigationAgent
  defp agent_for(:reproduce), do: ReproductionAgent
  defp agent_for(:fix), do: GrafanaAlertCodingAgent

  defp objective_instruction(:investigate),
    do: "Investigate this Forage item in the current repository without changing files."

  defp objective_instruction(:reproduce),
    do: "Try to reproduce this Forage item in the current repository without changing files."

  defp objective_instruction(:fix),
    do: "Fix this Forage item in the current repository with the smallest complete change."

  defp objective_outcome(:investigate, "investigated"), do: :investigated
  defp objective_outcome(:reproduce, "reproduced"), do: :reproduced
  defp objective_outcome(:reproduce, "not_reproduced"), do: :not_reproduced
  defp objective_outcome(:fix, "changed"), do: :fixed
  defp objective_outcome(:fix, "no_change"), do: :no_change
  defp objective_outcome(_objective, _outcome), do: :inconclusive

  defp publish_report_to_source(%Flight{input: %{"github_issue_id" => _id}} = run, result, opts) do
    issues_module = Keyword.get(opts, :issues_module, Issues)

    case issues_module.create_comment(
           run.repository,
           run.input["issue_number"],
           report_comment(run, result),
           opts
         ) do
      {:ok, _comment} -> :ok
      {:error, reason} -> {:error, {:report_publication_failed, reason}}
    end
  end

  defp publish_report_to_source(_run, _result, _opts), do: :ok

  defp report_comment(run, result) do
    validation =
      case result["validation"] do
        [] -> "- No validation commands were recorded."
        checks -> Enum.map_join(checks, "\n", &"- `#{&1}`")
      end

    """
    Hive completed a **#{Hive.Flights.objective_label(run.objective)}** Flight with the outcome **#{Hive.Flights.objective_outcome_label(String.to_existing_atom(result["objective_outcome"]))}**.

    #{result["summary"]}

    Validation:

    #{validation}

    [View the Flight](#{HiveWeb.Endpoint.url()}#{Hive.Flights.path(run)})
    """
  end

  defp notify_slack(%Flight{trigger: %{"source" => "slack"}} = run) do
    _ = Hive.Slack.Workers.UpdateFlightMessage.enqueue(run.id, run.status)
    :ok
  end

  defp notify_slack(_run), do: :ok

  defp format_error(reason) do
    reason
    |> Errors.sanitize_reason()
    |> inspect(limit: 20, printable_limit: 2_000)
    |> String.slice(0, 2_000)
  end

  defp normalize_runner(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_runner()

  defp normalize_runner(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> "disabled"
      runner -> runner
    end
  end

  defp normalize_runner(_value), do: "disabled"

  defp normalize_objective(value) when is_binary(value) do
    Enum.find(Flight.objectives(), :investigate, &(Atom.to_string(&1) == value))
  end

  defp normalize_objective(value) when value in [:investigate, :reproduce, :fix], do: value
  defp normalize_objective(_value), do: :investigate

  defp normalize_sandbox_options(value) when is_map(value), do: value
  defp normalize_sandbox_options(_value), do: %{}

  defp topic(forage_item_id), do: @topic_prefix <> forage_item_id
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
