defmodule Hive.Forage.CodingRuns.Sandboxes.Kubernetes do
  @moduledoc """
  Condukt sandbox backed by a Kubernetes Agent Sandbox resource.

  Agent Sandbox owns the isolated pod lifecycle and secure pod template.
  Condukt's Kubernetes sandbox continues to provide the file and command
  operations used by the coding harness.
  """

  @behaviour Condukt.Sandbox
  @behaviour Hive.Forage.CodingRuns.SandboxProvider

  alias Condukt.Sandbox
  alias Condukt.Sandbox.Kubernetes, as: ConduktKubernetes
  alias Condukt.Sandbox.Kubernetes.State, as: ConduktState
  alias Hive.Forage.CodingRuns.Sandboxes.KubernetesClient
  alias Hive.Forage.CodingRuns.Workspace

  @api_version "agents.x-k8s.io/v1beta1"
  @container_name "agent"
  @default_cwd "/workspace"
  @default_namespace "hive-sandboxes"
  @default_ready_timeout 120_000
  @poll_interval 1_000

  defstruct [
    :client,
    :conn,
    :namespace,
    :name,
    :pod_state,
    :delegate,
    :cwd
  ]

  @impl Hive.Forage.CodingRuns.SandboxProvider
  def configured?(options) when is_map(options) do
    present?(option(options, "namespace", @default_namespace)) and
      present?(option(options, "runtime_class_name", "gvisor")) and
      connection_configured?(options)
  end

  def configured?(_options), do: false

  @impl Sandbox
  def init(opts) do
    with {:ok, config} <- build_config(opts),
         {:ok, conn} <- config.client.connect(config),
         :ok <- config.client.create_sandbox(conn, sandbox_manifest(config)) do
      initialize_created_sandbox(config, conn)
    end
  end

  @impl Sandbox
  def shutdown(%__MODULE__{} = state) do
    state.client.delete_sandbox(state.conn, state.namespace, state.name)
  end

  @impl Sandbox
  def read_file(%__MODULE__{} = state, path),
    do: state.delegate.read_file(state.pod_state, path)

  @impl Sandbox
  def write_file(%__MODULE__{} = state, path, content),
    do: state.delegate.write_file(state.pod_state, path, content)

  @impl Sandbox
  def edit_file(%__MODULE__{} = state, path, old_text, new_text),
    do: state.delegate.edit_file(state.pod_state, path, old_text, new_text)

  @impl Sandbox
  def exec(%__MODULE__{} = state, command, opts),
    do: state.delegate.exec(state.pod_state, command, opts)

  @impl Sandbox
  def glob(%__MODULE__{} = state, pattern, opts),
    do: state.delegate.glob(state.pod_state, pattern, opts)

  @impl Sandbox
  def grep(%__MODULE__{} = state, pattern, opts),
    do: state.delegate.grep(state.pod_state, pattern, opts)

  @impl Sandbox
  def cwd(%__MODULE__{} = state), do: state.cwd

  @impl Hive.Forage.CodingRuns.SandboxProvider
  def runner_id(%Sandbox{module: __MODULE__, state: state}), do: state.name

  defp build_config(opts) do
    options = Keyword.get(opts, :provider_options, %{})
    id = Keyword.fetch!(opts, :id)
    timeout_minutes = Keyword.get(opts, :timeout_minutes, 30)

    config = %{
      api_version: @api_version,
      client: Keyword.get(opts, :client, KubernetesClient),
      conn: Keyword.get(opts, :conn),
      delegate: Keyword.get(opts, :delegate, ConduktKubernetes),
      namespace: option(options, "namespace", @default_namespace),
      name: sandbox_name(id),
      image: Keyword.get(opts, :image, "ubuntu:24.04"),
      image_pull_policy: option(options, "image_pull_policy", "IfNotPresent"),
      image_pull_secrets: option(options, "image_pull_secrets", []),
      runtime_class_name: option(options, "runtime_class_name", "gvisor"),
      node_selector: option(options, "node_selector", %{}),
      tolerations: option(options, "tolerations", []),
      service_account: option(options, "service_account"),
      run_as_user: option(options, "run_as_user", 1_000),
      cpus: Keyword.get(opts, :cpus, 2),
      memory: Keyword.get(opts, :memory, 4_096),
      disk: Keyword.get(opts, :disk, 8_192),
      timeout_minutes: timeout_minutes,
      ready_timeout: option(options, "ready_timeout_ms", @default_ready_timeout),
      setup_command: Keyword.get(opts, :setup_command, Workspace.default_setup_command()),
      source_archive: Keyword.fetch!(opts, :source_archive),
      base_branch: Keyword.fetch!(opts, :base_branch),
      cwd: @default_cwd,
      in_cluster: option(options, "in_cluster", false),
      kubeconfig: option(options, "kubeconfig"),
      context: option(options, "context")
    }

    validate_config(config)
  end

  defp validate_config(config) do
    validations = [
      {present?(config.namespace), :kubernetes_namespace_not_configured},
      {present?(config.runtime_class_name), :kubernetes_runtime_class_not_configured},
      {valid_image_pull_policy?(config.image_pull_policy), :invalid_image_pull_policy},
      {positive_integer?(config.run_as_user), :invalid_run_as_user},
      {positive_integer?(config.ready_timeout), :invalid_ready_timeout},
      {string_map?(config.node_selector), :invalid_node_selector},
      {map_list?(config.tolerations), :invalid_tolerations},
      {valid_image_pull_secrets?(config.image_pull_secrets), :invalid_image_pull_secrets}
    ]

    case Enum.find(validations, fn {valid?, _reason} -> not valid? end) do
      nil -> {:ok, config}
      {_valid?, reason} -> {:error, reason}
    end
  end

  defp initialize_created_sandbox(config, conn) do
    case wait_until_ready(config.client, conn, config) do
      {:ok, pod_name} ->
        config
        |> state(conn, pod_name)
        |> provision(config)

      {:error, reason} ->
        config.client.delete_sandbox(conn, config.namespace, config.name)
        {:error, reason}
    end
  end

  defp sandbox_manifest(config) do
    pod_spec = %{
      "runtimeClassName" => config.runtime_class_name,
      "automountServiceAccountToken" => false,
      "hostNetwork" => false,
      "hostPID" => false,
      "hostIPC" => false,
      "restartPolicy" => "Never",
      "terminationGracePeriodSeconds" => 10,
      "securityContext" => %{
        "runAsNonRoot" => true,
        "runAsUser" => config.run_as_user,
        "runAsGroup" => config.run_as_user,
        "fsGroup" => config.run_as_user,
        "seccompProfile" => %{"type" => "RuntimeDefault"}
      },
      "containers" => [container(config)],
      "volumes" => [
        %{
          "name" => "workspace",
          "emptyDir" => %{"sizeLimit" => "#{config.disk}Mi"}
        }
      ]
    }

    pod_spec =
      pod_spec
      |> maybe_put("serviceAccountName", config.service_account)
      |> maybe_put("nodeSelector", config.node_selector, &(map_size(&1) > 0))
      |> maybe_put("tolerations", config.tolerations, &(&1 != []))
      |> maybe_put("imagePullSecrets", image_pull_secrets(config.image_pull_secrets), &(&1 != []))

    %{
      "apiVersion" => config.api_version,
      "kind" => "Sandbox",
      "metadata" => %{
        "name" => config.name,
        "namespace" => config.namespace,
        "labels" => %{
          "app.kubernetes.io/name" => "hive-coding-sandbox",
          "app.kubernetes.io/managed-by" => "hive"
        }
      },
      "spec" => %{
        "operatingMode" => "Running",
        "shutdownPolicy" => "Delete",
        "shutdownTime" => shutdown_time(config.timeout_minutes),
        "service" => false,
        "podTemplate" => %{
          "metadata" => %{
            "labels" => %{"app.kubernetes.io/name" => "hive-coding-sandbox"}
          },
          "spec" => pod_spec
        }
      }
    }
  end

  defp container(config) do
    %{
      "name" => @container_name,
      "image" => config.image,
      "imagePullPolicy" => config.image_pull_policy,
      "command" => ["sleep", "infinity"],
      "workingDir" => config.cwd,
      "resources" => %{
        "requests" => %{"cpu" => to_string(config.cpus), "memory" => "#{config.memory}Mi"},
        "limits" => %{"cpu" => to_string(config.cpus), "memory" => "#{config.memory}Mi"}
      },
      "securityContext" => %{
        "allowPrivilegeEscalation" => false,
        "privileged" => false,
        "runAsNonRoot" => true,
        "runAsUser" => config.run_as_user,
        "capabilities" => %{"drop" => ["ALL"]}
      },
      "volumeMounts" => [%{"name" => "workspace", "mountPath" => config.cwd}]
    }
  end

  defp wait_until_ready(client, conn, config) do
    deadline = System.monotonic_time(:millisecond) + config.ready_timeout
    poll_until_ready(client, conn, config, deadline)
  end

  defp poll_until_ready(client, conn, config, deadline) do
    case client.get_sandbox(conn, config.namespace, config.name) do
      {:ok, sandbox} -> handle_sandbox_status(client, conn, config, deadline, sandbox)
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_sandbox_status(client, conn, config, deadline, sandbox) do
    case ready_condition(sandbox) do
      %{"status" => "True"} ->
        {:ok,
         get_in(sandbox, ["metadata", "annotations", "agents.x-k8s.io/pod-name"]) || config.name}

      %{"reason" => reason} when reason in ["PodFailed", "PodSucceeded", "SandboxExpired"] ->
        {:error, {:kubernetes_sandbox_not_ready, reason}}

      _other ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :kubernetes_sandbox_ready_timeout}
        else
          Process.sleep(@poll_interval)
          poll_until_ready(client, conn, config, deadline)
        end
    end
  end

  defp ready_condition(sandbox) do
    sandbox
    |> get_in(["status", "conditions"])
    |> List.wrap()
    |> Enum.find(&(&1["type"] == "Ready"))
  end

  defp state(config, conn, pod_name) do
    pod_state = %ConduktState{
      conn: conn,
      namespace: config.namespace,
      pod_name: pod_name,
      container: @container_name,
      base_cwd: config.cwd,
      id: config.name,
      delete_on_shutdown: false,
      owner_pid: self()
    }

    %__MODULE__{
      client: config.client,
      conn: conn,
      namespace: config.namespace,
      name: config.name,
      pod_state: pod_state,
      delegate: config.delegate,
      cwd: config.cwd
    }
  end

  defp provision(state, config) do
    with {:ok, %{exit_code: 0}} <- exec(state, config.setup_command, timeout: 300_000),
         :ok <- write_file(state, "/tmp/hive-source.tar.gz", config.source_archive),
         {:ok, %{exit_code: 0}} <-
           exec(state, Workspace.initialization_command(config.base_branch),
             cwd: "/",
             timeout: 120_000
           ) do
      {:ok, state}
    else
      {:ok, %{exit_code: status, output: output}} ->
        cleanup(state, {:sandbox_setup_failed, status, output})

      {:error, reason} ->
        cleanup(state, reason)
    end
  end

  defp cleanup(state, reason) do
    shutdown(state)
    {:error, reason}
  end

  defp connection_configured?(options) do
    option(options, "in_cluster", false) == true or present?(option(options, "kubeconfig"))
  end

  defp image_pull_secrets(secrets) do
    Enum.map(secrets, fn
      %{"name" => name} -> %{"name" => name}
      %{name: name} -> %{"name" => name}
      name when is_binary(name) -> %{"name" => name}
    end)
  end

  defp shutdown_time(timeout_minutes) do
    DateTime.utc_now()
    |> DateTime.add(timeout_minutes * 60 + 300, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp sandbox_name(id) do
    suffix =
      id
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9-]/, "-")
      |> String.trim("-")
      |> String.slice(0, 48)

    "hive-#{suffix}"
  end

  defp option(options, key, default \\ nil) do
    Map.get(options, key, default)
  end

  defp maybe_put(map, key, value), do: maybe_put(map, key, value, &(not is_nil(&1)))

  defp maybe_put(map, key, value, predicate) do
    if predicate.(value), do: Map.put(map, key, value), else: map
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp valid_image_pull_policy?(value), do: value in ["Always", "IfNotPresent", "Never"]

  defp string_map?(value) when is_map(value) do
    Enum.all?(value, fn {key, entry} -> is_binary(key) and is_binary(entry) end)
  end

  defp string_map?(_value), do: false

  defp map_list?(value) when is_list(value), do: Enum.all?(value, &is_map/1)
  defp map_list?(_value), do: false

  defp valid_image_pull_secrets?(value) when is_list(value) do
    Enum.all?(value, fn
      %{"name" => name} -> present?(name)
      %{name: name} -> present?(name)
      name -> present?(name)
    end)
  end

  defp valid_image_pull_secrets?(_value), do: false
end
