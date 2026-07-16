defmodule Hive.Forage.CodingRuns do
  @moduledoc """
  Durable, manually triggered coding-harness runs for Forage items.

  Grafana alerts are the first supported input. A run snapshots the alert and
  repository selection, executes a Condukt coding agent in the configured
  sandbox, and persists either a pull request or a report result.
  """

  import Ecto.Query

  alias Condukt.Sandbox
  alias Hive.Accounts.User
  alias Hive.Agents.Errors
  alias Hive.Agents.Sessions
  alias Hive.Audit
  alias Hive.Domains.GitHubRepository
  alias Hive.Forage.Agents.GrafanaAlertCodingAgent
  alias Hive.Forage.CodingRun
  alias Hive.Forage.CodingRunWorker
  alias Hive.Forage.CodingRuns.SandboxContract
  alias Hive.Forage.CodingRuns.Workspace
  alias Hive.Forage.GrafanaAlert
  alias Hive.Forage.Policy
  alias Hive.GitHub.Client
  alias Hive.GitHub.CodeChanges
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

    Hive.Agents.enabled?() and Client.configured?() and SandboxContract.configured?(configured)
  end

  def subscribe(forage_item_id) when is_binary(forage_item_id) do
    Phoenix.PubSub.subscribe(Hive.PubSub, topic(forage_item_id))
  end

  def list_for_item(forage_item_id) when is_binary(forage_item_id) do
    CodingRun
    |> where([run], run.forage_item_id == ^forage_item_id)
    |> order_by([run], desc: run.inserted_at)
    |> preload([:repository, :requested_by])
    |> Repo.all()
  end

  def get(id) when is_binary(id) do
    CodingRun
    |> preload([:repository, :requested_by])
    |> Repo.get(id)
  rescue
    Ecto.Query.CastError -> nil
  end

  def get_for_user(id, user) do
    if Policy.authorize?(:coding_run_read, user, nil), do: get(id), else: nil
  end

  def create_for_grafana_alert(alert, repository_id, user, opts \\ [])

  def create_for_grafana_alert(%GrafanaAlert{} = alert, repository_id, %User{} = user, opts)
      when is_binary(repository_id) do
    enabled? = Keyword.get(opts, :enabled?, &enabled?/0)

    cond do
      not Policy.authorize?(:coding_run_create, user, alert) ->
        {:error, :unauthorized}

      not enabled?.() ->
        {:error, :not_configured}

      true ->
        create_for_repository(alert, repository_id, user, opts)
    end
  end

  def create_for_grafana_alert(_alert, _repository_id, _user, _opts),
    do: {:error, :unauthorized}

  def execute(coding_run_id, opts \\ []) when is_binary(coding_run_id) do
    case get(coding_run_id) do
      nil ->
        :ok

      %CodingRun{status: status} when status in [:running, :succeeded, :failed] ->
        :ok

      %CodingRun{} = run ->
        Audit.put_context(%{interface: "worker", actor_kind: "system", actor_name: "Coding run"})

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

  defp create_for_repository(alert, repository_id, user, opts) do
    case Repo.get_by(GitHubRepository, id: repository_id, project_id: alert.project_id) do
      nil ->
        {:error, :repository_not_found}

      repository ->
        insert_run(alert, repository, user, opts)
    end
  end

  defp insert_run(alert, repository, user, opts) do
    runner =
      opts |> Keyword.get(:config, Application.get_env(:hive, :coding_runs, [])) |> config()

    attrs = %{
      forage_item_id: "grafana_alert:#{alert.id}",
      status: :queued,
      runner: runner.runner,
      repository_full_name: GitHubRepository.full_name(repository),
      repository_id: repository.id,
      requested_by_id: user.id,
      input: alert_input(alert, repository)
    }

    result =
      Repo.transaction(fn ->
        with {:ok, run} <- %CodingRun{} |> CodingRun.changeset(attrs) |> Repo.insert(),
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
        Audit.record("forage.coding_run.created", %{
          target_type: "coding_run",
          target_id: run.id,
          target_label: alert.title,
          metadata: %{
            "forage_item_id" => run.forage_item_id,
            "repository" => run.repository_full_name,
            "runner" => run.runner
          }
        })

        broadcast(run)
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
      case execute_in_sandbox(run, sandbox, sessions_module, conf) do
        {:ok, {agent_result, changes}} ->
          finish_execution(run, source, changes, agent_result, source_module, opts)

        {:error, reason} ->
          mark_failed(run.id, reason)
      end
    else
      {:error, reason} -> mark_failed(run.id, reason)
    end
  end

  defp finish_execution(run, source, changes, agent_result, source_module, opts) do
    case finish_result(run, source, changes, agent_result, source_module, opts) do
      {:ok, result} -> succeed_run(run.id, result)
      {:error, reason} -> mark_failed(run.id, reason)
    end
  end

  defp execute_in_sandbox(run, sandbox, sessions_module, conf) do
    try do
      maybe_store_runner_id(run, sandbox)

      with {:ok, agent_result} <-
             sessions_module.run(
               GrafanaAlertCodingAgent,
               prompt(run),
               sandbox: sandbox,
               cwd: Sandbox.cwd(sandbox),
               load_project_instructions: true,
               output: GrafanaAlertCodingAgent.output_schema(),
               max_turns: 80,
               timeout: :timer.minutes(conf.timeout_minutes)
             ),
           {:ok, changes} <- Workspace.collect_changes(sandbox) do
        {:ok, {agent_result, changes}}
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

  defp finish_result(run, _source, [], agent_result, _source_module, _opts) do
    {:ok, report_result(agent_result, run.repository_full_name)}
  end

  defp finish_result(run, source, changes, agent_result, source_module, opts) do
    attrs = publication_attrs(run, changes, agent_result)

    case source_module.publish(run.repository, source, changes, attrs, opts) do
      {:ok, pull_request} ->
        {:ok,
         %{
           "type" => "pull_request",
           "number" => pull_request.number,
           "title" => pull_request.title,
           "url" => pull_request.url,
           "repository" => run.repository_full_name,
           "summary" => result_value(agent_result, :summary),
           "validation" => result_value(agent_result, :validation, [])
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp report_result(agent_result, repository) do
    %{
      "type" => "report",
      "repository" => repository,
      "outcome" => result_value(agent_result, :outcome, "no_change"),
      "summary" => result_value(agent_result, :summary),
      "root_cause" => result_value(agent_result, :root_cause),
      "validation" => result_value(agent_result, :validation, [])
    }
  end

  defp publication_attrs(run, changes, agent_result) do
    title = "fix(forage): address #{String.slice(run.input["title"] || "Grafana alert", 0, 72)}"

    %{
      branch: "hive/grafana-alert-#{String.slice(run.id, 0, 8)}",
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

    This change was prepared from the Grafana alert **#{run.input["title"]}** in Hive.

    ## Root cause

    #{result_value(agent_result, :root_cause)}

    ## Approach

    Hive ran its coding harness against an isolated snapshot of `#{run.repository_full_name}` and published the returned file changes through the GitHub App.

    ## Impact

    The change is limited to the alert's linked repository and is ready for normal review.

    ## Validation

    #{validation}
    """
  end

  defp prompt(run) do
    labels = run.input["labels"] |> then(&JSON.encode!(&1 || %{})) |> prompt_field()

    """
    Address this Grafana alert in the current repository.

    Title: #{prompt_field(run.input["title"])}
    Summary: #{prompt_field(run.input["summary"] || "No summary was provided.")}
    Status: #{run.input["status"]}
    Project: #{prompt_field(run.input["project"])}
    Repository: #{run.repository_full_name}
    Labels: #{labels}

    Leave the workspace with the complete focused change and return the required structured result.
    """
  end

  defp alert_input(alert, repository) do
    project = if Ecto.assoc_loaded?(alert.project), do: alert.project, else: nil

    %{
      "kind" => "grafana_alert",
      "alert_id" => alert.id,
      "title" => alert.title,
      "summary" => alert.summary,
      "status" => Atom.to_string(alert.status),
      "labels" => alert.labels,
      "generator_url" => alert.generator_url,
      "project" => project && project.name,
      "project_id" => alert.project_id,
      "repository" => GitHubRepository.full_name(repository)
    }
  end

  defp claim_run(run) do
    now = now()

    query =
      from(candidate in CodingRun, where: candidate.id == ^run.id and candidate.status == :queued)

    case Repo.update_all(query,
           set: [status: :running, started_at: now, error: nil, updated_at: now]
         ) do
      {1, _rows} ->
        claimed_run = get(run.id)
        broadcast(claimed_run)
        {:ok, claimed_run}

      {0, _rows} ->
        :already_claimed
    end
  end

  defp maybe_store_runner_id(run, sandbox) do
    runner_id = SandboxContract.runner_id(sandbox)

    if runner_id do
      run
      |> CodingRun.changeset(%{runner_id: runner_id})
      |> Repo.update!()
    end

    :ok
  end

  defp succeed_run(id, result) do
    run = Repo.get!(CodingRun, id)

    run =
      run
      |> CodingRun.changeset(%{
        status: :succeeded,
        result: result,
        completed_at: now(),
        error: nil
      })
      |> Repo.update!()

    Audit.record(
      "forage.coding_run.completed",
      audit_attrs(run, %{"result_type" => result["type"]})
    )

    broadcast(run)
    :ok
  end

  defp mark_failed(id, reason) do
    case Repo.get(CodingRun, id) do
      nil ->
        :ok

      %CodingRun{status: status} when status in [:succeeded, :failed] ->
        :ok

      run ->
        error = format_error(reason)

        run =
          run
          |> CodingRun.changeset(%{status: :failed, error: error, completed_at: now()})
          |> Repo.update!()

        Audit.record("forage.coding_run.failed", audit_attrs(run, %{"error" => error}))
        broadcast(run)
        :ok
    end
  end

  defp fail_run(id, reason) do
    mark_failed(id, reason)
    :ok
  end

  defp audit_attrs(run, metadata) do
    %{
      target_type: "coding_run",
      target_id: run.id,
      target_label: run.input["title"],
      metadata:
        Map.merge(metadata, %{
          "forage_item_id" => run.forage_item_id,
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

  defp prompt_field(nil), do: "Unknown"

  defp prompt_field(value),
    do: value |> to_string() |> String.slice(0, @max_prompt_field_characters)

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

  defp normalize_sandbox_options(value) when is_map(value), do: value
  defp normalize_sandbox_options(_value), do: %{}

  defp topic(forage_item_id), do: @topic_prefix <> forage_item_id
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
