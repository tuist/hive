defmodule Hive.Forage.CodingRuns.Sandboxes.Microsandbox do
  @moduledoc false

  @behaviour Condukt.Sandbox
  @behaviour Hive.Forage.CodingRuns.SandboxProvider

  alias Condukt.Sandbox
  alias Hive.Forage.CodingRuns.Workspace

  @guest_workspace "/workspace"
  @default_home "/tmp/hive-msb"

  @impl Sandbox
  def init(opts) do
    with {:ok, executable} <- executable(opts),
         {:ok, directory} <-
           Workspace.prepare_local(
             Keyword.fetch!(opts, :source_archive),
             Keyword.fetch!(opts, :base_branch)
           ) do
      state = %{
        directory: directory,
        executable: executable,
        msb_home: Keyword.get(opts, :msb_home) || @default_home,
        name: sandbox_name(Keyword.get(opts, :id))
      }

      start(state, opts)
    end
  end

  @impl Sandbox
  def shutdown(state) do
    _result = command(state, ["remove", "--force", "--quiet", state.name])
    File.rm_rf(state.directory)
    :ok
  end

  @impl Sandbox
  def read_file(state, path) do
    with {:ok, path} <- guest_path(path),
         {:ok, %{exit_code: 0, output: output}} <-
           exec(state, "cat -- #{Workspace.shell_quote(path)}", timeout: 30_000) do
      {:ok, output}
    else
      {:ok, %{exit_code: _status}} -> {:error, :enoent}
      error -> error
    end
  end

  @impl Sandbox
  def write_file(state, path, content) do
    with {:ok, path} <- guest_path(path) do
      write_through_guest(state, path, content)
    end
  end

  @impl Sandbox
  def edit_file(state, path, old_text, new_text) do
    with {:ok, content} <- read_file(state, path) do
      replace_file_matches(state, path, content, old_text, new_text)
    end
  end

  @impl Sandbox
  def exec(state, command, opts) do
    with {:ok, cwd} <- guest_path(Keyword.get(opts, :cwd)) do
      timeout = Keyword.get(opts, :timeout, 120_000)

      args =
        [
          "exec",
          "--quiet",
          "--no-tty",
          "--workdir",
          cwd,
          "--timeout",
          "#{ceil(timeout / 1_000)}s"
        ] ++
          env_args(Keyword.get(opts, :env, [])) ++
          [state.name, "--", "/bin/bash", "-lc", command]

      case command(state, args) do
        {output, status} -> {:ok, %{output: output, exit_code: status}}
      end
    end
  end

  @impl Sandbox
  def glob(state, pattern, opts) do
    limit = normalize_limit(Keyword.get(opts, :limit, 1_000))

    with {:ok, cwd} <- guest_path(Keyword.get(opts, :cwd)),
         {:ok, pattern} <- safe_pattern(pattern),
         {:ok, %{exit_code: status, output: output}} when status in [0, 1] <-
           exec(
             state,
             "rg --files --hidden -g #{Workspace.shell_quote(pattern)} | head -n #{limit}",
             cwd: cwd,
             timeout: 30_000
           ) do
      {:ok, output |> String.split("\n", trim: true) |> Enum.take(limit)}
    else
      {:ok, %{exit_code: status, output: output}} ->
        {:error, {:command_failed, status, output}}

      error ->
        error
    end
  end

  @impl Sandbox
  def grep(state, pattern, opts) do
    limit = normalize_limit(Keyword.get(opts, :limit, 1_000))
    case_flag = if Keyword.get(opts, :case_sensitive, true), do: "", else: "-i"

    with {:ok, path} <- guest_path(Keyword.get(opts, :path)),
         {:ok, glob} <- safe_pattern(Keyword.get(opts, :glob, "**/*")),
         {:ok, %{exit_code: status, output: output}} when status in [0, 1] <-
           exec(
             state,
             "rg #{case_flag} --line-number --no-heading --color never " <>
               "-g #{Workspace.shell_quote(glob)} #{Workspace.shell_quote(pattern)} . " <>
               "| head -n #{limit}",
             cwd: path,
             timeout: 30_000
           ) do
      {:ok, parse_grep(output, limit)}
    else
      {:ok, %{exit_code: status, output: output}} ->
        {:error, {:command_failed, status, output}}

      error ->
        error
    end
  end

  @impl Sandbox
  def cwd(_state), do: @guest_workspace

  defp start(state, opts) do
    File.mkdir_p!(state.msb_home)
    workspace = Path.join(state.directory, "workspace")

    args = [
      "create",
      "--quiet",
      "--name",
      state.name,
      "--replace",
      "--cpus",
      to_string(Keyword.get(opts, :cpus, 2)),
      "--memory",
      "#{Keyword.get(opts, :memory, 2048)}M",
      "--volume",
      "#{workspace}:#{@guest_workspace}",
      "--workdir",
      @guest_workspace,
      "--shell",
      "/bin/bash",
      Keyword.get(opts, :image, "ubuntu:24.04")
    ]

    case command(state, args) do
      {_output, 0} -> provision(state, opts)
      {output, status} -> cleanup(state, {:sandbox_start_failed, status, output})
    end
  end

  defp provision(state, opts) do
    setup_command = Keyword.get(opts, :setup_command, Workspace.default_setup_command())

    case exec(state, setup_command, timeout: 300_000) do
      {:ok, %{exit_code: 0}} ->
        {:ok, state}

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

  defp command(state, args) do
    System.cmd("/bin/sh", ["-c", "exec \"$0\" \"$@\" </dev/null", state.executable | args],
      env: [{"MSB_HOME", state.msb_home}],
      stderr_to_stdout: true
    )
  end

  defp executable(opts) do
    case Keyword.get(opts, :executable) || System.find_executable("msb") do
      nil -> {:error, :microsandbox_not_installed}
      path -> {:ok, path}
    end
  end

  defp guest_path(nil), do: {:ok, @guest_workspace}
  defp guest_path(""), do: {:ok, @guest_workspace}

  defp guest_path(path) do
    expanded =
      if Path.type(path) == :absolute,
        do: Path.expand(path),
        else: Path.expand(path, @guest_workspace)

    if expanded == @guest_workspace or String.starts_with?(expanded, @guest_workspace <> "/"),
      do: {:ok, expanded},
      else: {:error, :outside_workspace}
  end

  defp workspace_relative(path) do
    with {:ok, guest_path} <- guest_path(path) do
      {:ok, Path.relative_to(guest_path, @guest_workspace)}
    end
  end

  defp safe_pattern(pattern) when is_binary(pattern) do
    components = Path.split(pattern)

    cond do
      ".." in components ->
        {:error, :outside_workspace}

      Path.type(pattern) == :absolute ->
        case workspace_relative(pattern) do
          {:ok, relative} -> {:ok, relative}
          error -> error
        end

      true ->
        {:ok, pattern}
    end
  end

  defp env_args(env) do
    Enum.flat_map(env, fn {key, value} -> ["--env", "#{key}=#{value}"] end)
  end

  defp write_through_guest(state, path, content) do
    upload_name = ".hive-upload-#{System.unique_integer([:positive, :monotonic])}"
    host_upload = Path.join([state.directory, "workspace", upload_name])
    guest_upload = Path.join(@guest_workspace, upload_name)

    try do
      with :ok <- File.write(host_upload, content, [:exclusive]),
           {:ok, %{exit_code: 0}} <-
             exec(
               state,
               "mkdir -p -- #{Workspace.shell_quote(Path.dirname(path))} && " <>
                 "mv -f -- #{Workspace.shell_quote(guest_upload)} #{Workspace.shell_quote(path)}",
               timeout: 30_000
             ) do
        :ok
      else
        {:ok, %{exit_code: status, output: output}} ->
          {:error, {:command_failed, status, output}}

        error ->
          error
      end
    after
      File.rm(host_upload)
    end
  end

  defp replace_file_matches(state, path, content, old_text, new_text) do
    case :binary.matches(content, old_text) do
      [] ->
        {:ok, %{occurrences: 0, content: content}}

      [_match] ->
        updated = String.replace(content, old_text, new_text, global: false)

        with :ok <- write_file(state, path, updated) do
          {:ok, %{occurrences: 1, content: updated}}
        end

      matches ->
        {:ok, %{occurrences: length(matches), content: content}}
    end
  end

  defp parse_grep(output, limit) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce([], &parse_grep_line/2)
    |> Enum.reverse()
    |> Enum.take(limit)
  end

  defp parse_grep_line(line, acc) do
    with [path, line_number, text] <- String.split(line, ":", parts: 3),
         {number, ""} <- Integer.parse(line_number) do
      [%{path: String.trim_leading(path, "./"), line_number: number, line: text} | acc]
    else
      _other -> acc
    end
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: min(limit, 10_000)
  defp normalize_limit(_limit), do: 1_000

  defp sandbox_name(nil),
    do: "hive-#{System.unique_integer([:positive, :monotonic])}"

  defp sandbox_name(id) do
    id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_.-]/, "-")
    |> then(&("hive-" <> &1))
    |> String.slice(0, 120)
  end
end
