defmodule Hive.Forage.CodingRuns.Sandboxes.KubernetesTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Hive.Forage.CodingRuns.Sandboxes.Kubernetes

  defmodule Client do
    def connect(config), do: {:ok, config.conn}

    def create_sandbox(conn, manifest) do
      send(conn.test_pid, {:sandbox_created, manifest})
      :ok
    end

    def get_sandbox(_conn, _namespace, name) do
      {:ok,
       %{
         "metadata" => %{
           "name" => name,
           "annotations" => %{"agents.x-k8s.io/pod-name" => "#{name}-pod"}
         },
         "status" => %{
           "conditions" => [%{"type" => "Ready", "status" => "True"}]
         }
       }}
    end

    def delete_sandbox(conn, namespace, name) do
      send(conn.test_pid, {:sandbox_deleted, namespace, name})
      :ok
    end
  end

  defmodule Delegate do
    def read_file(state, path) do
      send(state.conn.test_pid, {:read_file, state, path})
      {:ok, "contents"}
    end

    def write_file(state, path, content) do
      send(state.conn.test_pid, {:write_file, state, path, content})
      :ok
    end

    def edit_file(state, path, old_text, new_text) do
      send(state.conn.test_pid, {:edit_file, state, path, old_text, new_text})
      {:ok, %{occurrences: 1, content: new_text}}
    end

    def exec(state, command, opts) do
      send(state.conn.test_pid, {:exec, state, command, opts})

      if command == "fail-setup",
        do: {:ok, %{exit_code: 13, output: "setup failed"}},
        else: {:ok, %{exit_code: 0, output: "ok"}}
    end

    def glob(state, pattern, opts) do
      send(state.conn.test_pid, {:glob, state, pattern, opts})
      {:ok, ["lib/hive.ex"]}
    end

    def grep(state, pattern, opts) do
      send(state.conn.test_pid, {:grep, state, pattern, opts})
      {:ok, [%{path: "lib/hive.ex", line_number: 1, line: pattern}]}
    end
  end

  defmodule FailedClient do
    defdelegate connect(config), to: Client
    defdelegate create_sandbox(conn, manifest), to: Client
    defdelegate delete_sandbox(conn, namespace, name), to: Client

    def get_sandbox(_conn, _namespace, name) do
      {:ok,
       %{
         "metadata" => %{"name" => name},
         "status" => %{
           "conditions" => [
             %{"type" => "Ready", "status" => "False", "reason" => "PodFailed"}
           ]
         }
       }}
    end
  end

  test "creates a hardened Agent Sandbox and delegates Condukt operations" do
    conn = %{test_pid: self()}

    assert {:ok, sandbox} =
             Sandbox.new(Kubernetes,
               id: "run-123",
               image: "ghcr.io/tuist/hive-coding-sandbox:sha-example",
               cpus: 2,
               memory: 4096,
               disk: 8192,
               timeout_minutes: 30,
               setup_command: "true",
               source_archive: "compressed-source",
               base_branch: "main",
               provider_options: %{
                 "in_cluster" => true,
                 "namespace" => "hive-sandboxes",
                 "image_pull_policy" => "Always",
                 "runtime_class_name" => "gvisor",
                 "node_selector" => %{"hive.tuist.dev/workload" => "coding-sandbox"},
                 "tolerations" => [
                   %{
                     "key" => "hive.tuist.dev/workload",
                     "operator" => "Equal",
                     "value" => "coding-sandbox",
                     "effect" => "NoSchedule"
                   }
                 ],
                 "image_pull_secrets" => ["ghcr-pull"]
               },
               client: Client,
               conn: conn,
               delegate: Delegate
             )

    assert_receive {:sandbox_created, manifest}
    assert manifest["apiVersion"] == "agents.x-k8s.io/v1beta1"
    assert manifest["kind"] == "Sandbox"
    assert manifest["metadata"]["name"] == "hive-run-123"
    assert manifest["metadata"]["namespace"] == "hive-sandboxes"
    assert manifest["spec"]["shutdownPolicy"] == "Delete"
    assert manifest["spec"]["service"] == false

    pod_spec = manifest["spec"]["podTemplate"]["spec"]
    assert pod_spec["runtimeClassName"] == "gvisor"
    assert pod_spec["automountServiceAccountToken"] == false
    assert pod_spec["hostNetwork"] == false
    assert pod_spec["hostPID"] == false
    assert pod_spec["hostIPC"] == false
    assert pod_spec["nodeSelector"] == %{"hive.tuist.dev/workload" => "coding-sandbox"}
    assert pod_spec["imagePullSecrets"] == [%{"name" => "ghcr-pull"}]
    assert get_in(pod_spec, ["securityContext", "seccompProfile", "type"]) == "RuntimeDefault"

    [container] = pod_spec["containers"]
    assert container["name"] == "agent"
    assert container["imagePullPolicy"] == "Always"
    assert container["resources"]["limits"] == %{"cpu" => "2", "memory" => "4096Mi"}
    assert container["securityContext"]["allowPrivilegeEscalation"] == false
    assert container["securityContext"]["capabilities"] == %{"drop" => ["ALL"]}
    assert get_in(pod_spec, ["volumes", Access.at(0), "emptyDir", "sizeLimit"]) == "8192Mi"

    assert_receive {:exec, %{pod_name: "hive-run-123-pod"}, "true", [timeout: 300_000]}

    assert_receive {:write_file, %{pod_name: "hive-run-123-pod"}, "/tmp/hive-source.tar.gz",
                    "compressed-source"}

    assert_receive {:exec, %{pod_name: "hive-run-123-pod"}, initialization_command,
                    [cwd: "/", timeout: 120_000]}

    assert initialization_command =~ "git tag hive-base"
    assert Kubernetes.runner_id(sandbox) == "hive-run-123"
    assert Sandbox.cwd(sandbox) == "/workspace"
    assert {:ok, "contents"} = Sandbox.read(sandbox, "/workspace/mix.exs")
    assert {:ok, %{exit_code: 0}} = Sandbox.exec(sandbox, "mix test")
    assert {:ok, ["lib/hive.ex"]} = Sandbox.glob(sandbox, "**/*.ex")
    assert {:ok, [_match]} = Sandbox.grep(sandbox, "defmodule")
    assert :ok = Sandbox.shutdown(sandbox)
    assert_receive {:sandbox_deleted, "hive-sandboxes", "hive-run-123"}
  end

  test "deletes the Agent Sandbox when provisioning fails" do
    assert {:error, {:sandbox_setup_failed, 13, "setup failed"}} =
             Sandbox.new(Kubernetes,
               id: "failed-run",
               setup_command: "fail-setup",
               source_archive: "source",
               base_branch: "main",
               provider_options: %{"in_cluster" => true},
               client: Client,
               conn: %{test_pid: self()},
               delegate: Delegate
             )

    assert_receive {:sandbox_deleted, "hive-sandboxes", "hive-failed-run"}
  end

  test "deletes the Agent Sandbox when its pod fails before becoming ready" do
    assert {:error, {:kubernetes_sandbox_not_ready, "PodFailed"}} =
             Sandbox.new(Kubernetes,
               id: "unready-run",
               setup_command: "true",
               source_archive: "source",
               base_branch: "main",
               provider_options: %{"in_cluster" => true},
               client: FailedClient,
               conn: %{test_pid: self()},
               delegate: Delegate
             )

    assert_receive {:sandbox_deleted, "hive-sandboxes", "hive-unready-run"}
    refute_receive {:exec, _state, _command, _options}
  end

  test "requires a runtime class and Kubernetes connection mode" do
    refute Kubernetes.configured?(%{})
    refute Kubernetes.configured?(%{"in_cluster" => true, "runtime_class_name" => ""})
    assert Kubernetes.configured?(%{"in_cluster" => true})

    assert Kubernetes.configured?(%{
             "kubeconfig" => "/tmp/example-kubeconfig",
             "runtime_class_name" => "gvisor"
           })
  end
end
