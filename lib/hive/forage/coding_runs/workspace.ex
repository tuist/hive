defmodule Hive.Forage.CodingRuns.Workspace do
  @moduledoc false

  alias Condukt.Sandbox

  @base_tag "hive-base"
  @max_changed_files 200
  @max_changed_file_bytes 5 * 1024 * 1024
  @max_total_change_bytes 20 * 1024 * 1024
  @default_setup_command "apt-get -o Acquire::ForceIPv4=true update -qq && DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y -qq git ripgrep ca-certificates && git config --global --add safe.directory /workspace"

  def default_setup_command, do: @default_setup_command

  def prepare_local(archive, branch) when is_binary(archive) and is_binary(branch) do
    with {:ok, directory} <- Briefly.create(directory: true),
         :ok <- extract_archive(archive, directory),
         :ok <- initialize_git(directory, branch) do
      {:ok, directory}
    end
  end

  def initialization_command(branch) do
    branch = shell_quote(branch)

    """
    set -e
    mkdir -p /workspace
    tar -xzf /tmp/hive-source.tar.gz --strip-components=1 -C /workspace
    cd /workspace
    git init --initial-branch=#{branch}
    git config user.name Hive
    git config user.email hive@example.invalid
    git add --all
    git commit --quiet -m 'Hive coding run baseline'
    git tag #{@base_tag}
    """
  end

  def collect_changes(%Sandbox{} = sandbox) do
    with {:ok, tracked_output} <-
           command_output(sandbox, "git diff --name-status -z #{@base_tag}"),
         {:ok, untracked_output} <-
           command_output(sandbox, "git ls-files --others --exclude-standard -z"),
         {:ok, tracked} <- parse_name_status(tracked_output),
         untracked <- parse_null_paths(untracked_output),
         specs <- merge_specs(tracked, untracked),
         :ok <- validate_change_count(specs) do
      read_changes(sandbox, specs)
    end
  end

  defp extract_archive(archive, directory) do
    archive_path = Path.join(directory, "source.tar.gz")
    workspace_path = Path.join(directory, "workspace")

    with :ok <- File.write(archive_path, archive),
         :ok <- File.mkdir(workspace_path),
         {_, 0} <-
           System.cmd("tar", ["-xzf", archive_path, "--strip-components=1", "-C", workspace_path]) do
      File.rm(archive_path)
      :ok
    else
      {:error, reason} -> {:error, reason}
      {output, status} -> {:error, {:archive_extract_failed, status, output}}
    end
  end

  defp initialize_git(directory, branch) do
    workspace = Path.join(directory, "workspace")

    commands = [
      ["init", "--initial-branch=#{branch}"],
      ["config", "user.name", "Hive"],
      ["config", "user.email", "hive@example.invalid"],
      ["add", "--all"],
      ["commit", "--quiet", "-m", "Hive coding run baseline"],
      ["tag", @base_tag]
    ]

    Enum.reduce_while(commands, :ok, fn args, :ok ->
      case System.cmd("git", args, cd: workspace, stderr_to_stdout: true) do
        {_output, 0} -> {:cont, :ok}
        {output, status} -> {:halt, {:error, {:git_init_failed, status, output}}}
      end
    end)
  end

  defp parse_name_status(""), do: {:ok, []}

  defp parse_name_status(output) do
    output
    |> parse_null_paths()
    |> parse_name_status_tokens([])
  end

  defp parse_name_status_tokens([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_name_status_tokens([status, old_path, new_path | rest], acc)
       when is_binary(status) do
    if String.starts_with?(status, ["R", "C"]) do
      entries = [%{path: old_path, deleted?: true}, %{path: new_path, deleted?: false}]
      parse_name_status_tokens(rest, Enum.reverse(entries) ++ acc)
    else
      parse_name_status_tokens([status, old_path, new_path | rest], acc, :regular)
    end
  end

  defp parse_name_status_tokens([status, path | rest], acc) do
    parse_name_status_tokens(rest, [
      %{path: path, deleted?: String.starts_with?(status, "D")} | acc
    ])
  end

  defp parse_name_status_tokens(_tokens, _acc), do: {:error, :invalid_git_status}

  defp parse_name_status_tokens([status, path | rest], acc, :regular) do
    parse_name_status_tokens(rest, [
      %{path: path, deleted?: String.starts_with?(status, "D")} | acc
    ])
  end

  defp merge_specs(tracked, untracked) do
    tracked_by_path = Map.new(tracked, &{&1.path, &1})

    untracked
    |> Enum.reduce(tracked_by_path, fn path, acc ->
      Map.put_new(acc, path, %{path: path, deleted?: false})
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.path)
  end

  defp read_changes(sandbox, specs) do
    Enum.reduce_while(specs, {:ok, {[], 0}}, fn spec, {:ok, {changes, total_bytes}} ->
      case read_change(sandbox, spec) do
        {:ok, change} ->
          append_change(change, changes, total_bytes)

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, {changes, _total_bytes}} -> {:ok, Enum.reverse(changes)}
      error -> error
    end
  end

  defp append_change(change, changes, total_bytes) do
    new_total = total_bytes + change_size(change)

    if new_total <= @max_total_change_bytes,
      do: {:cont, {:ok, {[change | changes], new_total}}},
      else: {:halt, {:error, :change_set_too_large}}
  end

  defp read_change(_sandbox, %{deleted?: true} = spec) do
    {:ok, Map.merge(spec, %{content: nil, mode: "100644"})}
  end

  defp read_change(sandbox, spec) do
    with {:ok, content} <- Sandbox.read(sandbox, spec.path),
         :ok <- validate_change_size(content),
         {:ok, mode_output} <-
           command_output(
             sandbox,
             "if [ -x #{shell_quote(spec.path)} ]; then printf 100755; else printf 100644; fi"
           ) do
      {:ok, Map.merge(spec, %{content: content, mode: String.trim(mode_output)})}
    end
  end

  defp validate_change_count(specs) do
    if length(specs) <= @max_changed_files, do: :ok, else: {:error, :too_many_changed_files}
  end

  defp validate_change_size(content) do
    if byte_size(content) <= @max_changed_file_bytes,
      do: :ok,
      else: {:error, :changed_file_too_large}
  end

  defp change_size(%{content: content}) when is_binary(content), do: byte_size(content)
  defp change_size(_change), do: 0

  defp command_output(sandbox, command) do
    case Sandbox.exec(sandbox, command, timeout: 30_000) do
      {:ok, %{exit_code: 0, output: output}} -> {:ok, output}
      {:ok, %{exit_code: status, output: output}} -> {:error, {:command_failed, status, output}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_null_paths(output) do
    String.split(output, <<0>>, trim: true)
  end

  def shell_quote(value) do
    "'" <> String.replace(to_string(value), "'", "'\"'\"'") <> "'"
  end
end
