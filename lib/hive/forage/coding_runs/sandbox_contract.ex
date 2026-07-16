defmodule Hive.Forage.CodingRuns.SandboxContract do
  @moduledoc false

  alias Condukt.Sandbox
  alias Hive.Forage.CodingRun
  alias Hive.Forage.CodingRuns.Sandboxes.Kubernetes
  alias Hive.Forage.CodingRuns.Sandboxes.KubernetesClient
  alias Hive.Forage.CodingRuns.Sandboxes.Microsandbox
  alias Hive.Forage.CodingRuns.Workspace

  @built_in_modules %{
    "kubernetes" => Kubernetes,
    "microsandbox" => Microsandbox
  }

  @required_callbacks [
    init: 1,
    shutdown: 1,
    read_file: 2,
    write_file: 3,
    edit_file: 4,
    exec: 3,
    glob: 3,
    grep: 3,
    cwd: 1
  ]

  def configured?(conf) do
    with {:ok, module} <- resolve(conf),
         true <- valid_module?(module) do
      provider_configured?(module, conf)
    else
      _other -> false
    end
  rescue
    _error -> false
  end

  def new(%CodingRun{} = run, source, conf, opts \\ []) do
    with :ok <- ensure_current_provider(run.runner, conf),
         {:ok, module} <- resolve(%{conf | runner: run.runner}),
         true <- valid_module?(module),
         true <- provider_configured?(module, conf),
         {:ok, sandbox} <-
           Sandbox.new(module, sandbox_options(module, run, source, conf, opts)) do
      provision_custom_sandbox(sandbox, module, source, conf)
    else
      false -> {:error, :sandbox_provider_not_configured}
      {:error, _reason} = error -> error
    end
  end

  def runner_id(%Sandbox{module: module} = sandbox) do
    if function_exported?(module, :runner_id, 1) do
      case module.runner_id(sandbox) do
        runner_id when is_binary(runner_id) and runner_id != "" -> runner_id
        _other -> nil
      end
    end
  end

  def resolve(%{runner: "disabled"}), do: {:error, :disabled}

  def resolve(%{runner: runner} = conf) when is_binary(runner) do
    case Map.fetch(@built_in_modules, runner) do
      {:ok, module} -> {:ok, module}
      :error -> resolve_custom_module(conf.sandbox_module)
    end
  end

  def resolve(_conf), do: {:error, :invalid_sandbox_provider}

  defp resolve_custom_module(module) when is_atom(module), do: {:ok, module}

  defp resolve_custom_module(module) when is_binary(module) do
    module
    |> String.trim()
    |> String.trim_leading("Elixir.")
    |> String.split(".", trim: true)
    |> Module.safe_concat()
    |> then(&{:ok, &1})
  rescue
    ArgumentError -> {:error, :sandbox_module_not_found}
  end

  defp resolve_custom_module(_module), do: {:error, :sandbox_module_not_configured}

  defp valid_module?(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        Enum.all?(@required_callbacks, fn {name, arity} ->
          function_exported?(module, name, arity)
        end)

      {:error, _reason} ->
        false
    end
  end

  defp provider_configured?(Microsandbox, _conf),
    do: not is_nil(System.find_executable("msb"))

  defp provider_configured?(Kubernetes, %{sandbox_options: options}),
    do: Kubernetes.configured?(options)

  defp provider_configured?(module, conf) do
    if function_exported?(module, :configured?, 1) do
      module.configured?(conf.sandbox_options)
    else
      true
    end
  end

  defp ensure_current_provider(runner, %{runner: runner}), do: :ok
  defp ensure_current_provider(runner, _conf) when is_map_key(@built_in_modules, runner), do: :ok
  defp ensure_current_provider(_runner, _conf), do: {:error, :sandbox_provider_changed}

  defp sandbox_options(module, run, source, conf, opts) do
    common = [
      runner: run.runner,
      image: conf.image,
      cpus: conf.cpus,
      memory: conf.memory,
      disk: conf.disk,
      timeout_minutes: conf.timeout_minutes,
      provider_options: conf.sandbox_options,
      id: run.id
    ]

    case module do
      Microsandbox ->
        common ++
          [
            source_archive: source.archive,
            base_branch: source.base_branch,
            setup_command: conf.setup_command,
            msb_home: conf.microsandbox_home
          ]

      Kubernetes ->
        common ++
          [
            source_archive: source.archive,
            base_branch: source.base_branch,
            setup_command: conf.setup_command,
            client: Keyword.get(opts, :kubernetes_client, KubernetesClient),
            conn: Keyword.get(opts, :kubernetes_conn),
            delegate: Keyword.get(opts, :kubernetes_delegate, Condukt.Sandbox.Kubernetes)
          ]

      _custom ->
        common
    end
  end

  defp provision_custom_sandbox(sandbox, module, _source, _conf)
       when module in [Microsandbox, Kubernetes],
       do: {:ok, sandbox}

  defp provision_custom_sandbox(sandbox, _module, source, conf) do
    with {:ok, %{exit_code: 0}} <-
           Sandbox.exec(sandbox, conf.setup_command, timeout: 300_000),
         :ok <- Sandbox.write(sandbox, "/tmp/hive-source.tar.gz", source.archive),
         {:ok, %{exit_code: 0}} <-
           Sandbox.exec(sandbox, Workspace.initialization_command(source.base_branch),
             cwd: "/",
             timeout: 120_000
           ) do
      {:ok, sandbox}
    else
      {:ok, %{exit_code: status, output: output}} ->
        shutdown_with_error(sandbox, {:sandbox_setup_failed, status, output})

      {:error, reason} ->
        shutdown_with_error(sandbox, reason)
    end
  end

  defp shutdown_with_error(sandbox, reason) do
    Sandbox.shutdown(sandbox)
    {:error, reason}
  end
end
