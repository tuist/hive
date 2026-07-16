defmodule Hive.Forage.CodingRuns.WorkspaceTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox
  alias Hive.Forage.CodingRuns.Workspace

  test "collects added, changed, deleted, and executable files" do
    source = source_archive()
    {:ok, directory} = Workspace.prepare_local(source, "main")
    workspace = Path.join(directory, "workspace")
    {:ok, sandbox} = Sandbox.new(Condukt.Sandbox.Local, cwd: workspace)

    on_exit(fn ->
      Sandbox.shutdown(sandbox)
      File.rm_rf(directory)
    end)

    File.write!(Path.join(workspace, "changed.txt"), "after\n")
    File.rm!(Path.join(workspace, "deleted.txt"))
    File.write!(Path.join(workspace, "added.txt"), "added\n")
    executable = Path.join(workspace, "run.sh")
    File.write!(executable, "#!/bin/sh\n")
    File.chmod!(executable, 0o755)

    assert {:ok, changes} = Workspace.collect_changes(sandbox)
    changes = Map.new(changes, &{&1.path, &1})

    assert changes["changed.txt"].content == "after\n"
    assert changes["deleted.txt"].deleted?
    assert changes["deleted.txt"].content == nil
    assert changes["added.txt"].content == "added\n"
    assert changes["run.sh"].mode == "100755"
  end

  defp source_archive do
    {:ok, directory} = Briefly.create(directory: true)
    source = Path.join(directory, "source")
    archive = Path.join(directory, "source.tar.gz")
    File.mkdir_p!(source)
    File.write!(Path.join(source, "changed.txt"), "before\n")
    File.write!(Path.join(source, "deleted.txt"), "delete me\n")
    {_, 0} = System.cmd("tar", ["-czf", archive, "-C", directory, "source"])
    File.read!(archive)
  end
end
