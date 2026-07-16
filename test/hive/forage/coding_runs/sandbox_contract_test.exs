defmodule Hive.Forage.CodingRuns.SandboxContractTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Hive.Forage.CodingRun
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.CodingRuns.SandboxContract
  alias Hive.Forage.CodingRuns.Sandboxes.Kubernetes
  alias Hive.Forage.CodingRuns.Sandboxes.Microsandbox

  defmodule CustomSandbox do
    @behaviour Condukt.Sandbox
    @behaviour Hive.Forage.CodingRuns.SandboxProvider

    @impl Hive.Forage.CodingRuns.SandboxProvider
    def configured?(%{"token" => token}), do: is_binary(token) and token != ""
    def configured?(_options), do: false

    @impl Condukt.Sandbox
    def init(opts) do
      send(opts[:provider_options]["test_pid"], {:sandbox_options, opts})
      {:ok, %{cwd: "/workspace", test_pid: opts[:provider_options]["test_pid"]}}
    end

    @impl Condukt.Sandbox
    def shutdown(_state), do: :ok

    @impl Condukt.Sandbox
    def read_file(_state, _path), do: {:error, :enoent}

    @impl Condukt.Sandbox
    def write_file(state, path, content) do
      send(state.test_pid, {:sandbox_write, path, content})
      :ok
    end

    @impl Condukt.Sandbox
    def edit_file(_state, _path, _old_text, _new_text),
      do: {:ok, %{occurrences: 0, content: ""}}

    @impl Condukt.Sandbox
    def exec(state, command, opts) do
      send(state.test_pid, {:sandbox_exec, command, opts})
      {:ok, %{exit_code: 0, output: ""}}
    end

    @impl Condukt.Sandbox
    def glob(_state, _pattern, _opts), do: {:ok, []}

    @impl Condukt.Sandbox
    def grep(_state, _pattern, _opts), do: {:ok, []}

    @impl Condukt.Sandbox
    def cwd(state), do: state.cwd

    @impl Hive.Forage.CodingRuns.SandboxProvider
    def runner_id(%Sandbox{module: __MODULE__}), do: "daytona-123"
  end

  defmodule IncompleteSandbox do
    def init(_opts), do: {:ok, %{}}
  end

  test "resolves the built-in providers" do
    assert {:ok, Microsandbox} = SandboxContract.resolve(%{runner: "microsandbox"})
    assert {:ok, Kubernetes} = SandboxContract.resolve(%{runner: "kubernetes"})
  end

  test "initializes a runtime-configured sandbox with common and provider options" do
    provider_options = %{"test_pid" => self(), "token" => "placeholder-token"}

    conf =
      CodingRuns.config(
        runner: "daytona",
        sandbox_module: Atom.to_string(CustomSandbox),
        sandbox_options: provider_options,
        image: "example.invalid/coding:1",
        setup_command: "true"
      )

    run = %CodingRun{id: Ecto.UUID.generate(), runner: "daytona"}
    source = %{archive: "archive", base_branch: "main"}

    assert SandboxContract.configured?(conf)
    assert {:ok, sandbox} = SandboxContract.new(run, source, conf)
    assert SandboxContract.runner_id(sandbox) == "daytona-123"

    assert_receive {:sandbox_options, opts}
    assert opts[:runner] == "daytona"
    assert opts[:image] == "example.invalid/coding:1"
    assert opts[:provider_options] == provider_options
    refute Keyword.has_key?(opts, :source_archive)

    assert_receive {:sandbox_exec, "true", [timeout: 300_000]}
    assert_receive {:sandbox_write, "/tmp/hive-source.tar.gz", "archive"}
    assert_receive {:sandbox_exec, initialization_command, [cwd: "/", timeout: 120_000]}
    assert initialization_command =~ "git tag hive-base"
  end

  test "rejects missing, incomplete, and changed custom providers" do
    refute SandboxContract.configured?(CodingRuns.config(runner: "daytona"))

    refute SandboxContract.configured?(
             CodingRuns.config(runner: "daytona", sandbox_module: IncompleteSandbox)
           )

    conf =
      CodingRuns.config(
        runner: "daytona",
        sandbox_module: CustomSandbox,
        sandbox_options: %{"test_pid" => self(), "token" => "placeholder-token"}
      )

    run = %CodingRun{id: Ecto.UUID.generate(), runner: "e2b"}
    source = %{archive: "archive", base_branch: "main"}

    assert {:error, :sandbox_provider_changed} = SandboxContract.new(run, source, conf)
  end
end
