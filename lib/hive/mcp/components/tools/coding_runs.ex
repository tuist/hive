defmodule Hive.MCP.Components.Tools.CodingRuns do
  @moduledoc false

  def coding_run_json(run) do
    %{
      id: run.id,
      forage_item_id: run.forage_item_id,
      status: Atom.to_string(run.status),
      runner: run.runner,
      repository: run.repository_full_name,
      result: run.result,
      error: run.error,
      started_at: iso8601(run.started_at),
      completed_at: iso8601(run.completed_at),
      inserted_at: iso8601(run.inserted_at),
      updated_at: iso8601(run.updated_at)
    }
  end

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp iso8601(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
end
