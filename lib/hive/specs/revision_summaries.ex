defmodule Hive.Specs.RevisionSummaries do
  @moduledoc """
  Describes a spec revision from deterministic changes between snapshots.
  """

  alias Hive.Specs.Revision

  def describe(%Revision{revision: 1, status: status}, nil) do
    "Created the initial #{humanize_status(status)} proposal."
  end

  def describe(%Revision{} = revision, %Revision{} = previous) do
    revision
    |> changes(previous)
    |> Enum.map(&format_change/1)
    |> humanize_changes()
  end

  def describe(%Revision{}, nil), do: "Saved the revision."

  def changes(%Revision{}, nil), do: []

  def changes(%Revision{} = revision, %Revision{} = previous) do
    [
      revision.title != previous.title && :renamed,
      revision.status != previous.status &&
        {:status_changed, previous.status, revision.status},
      revision.body != previous.body && body_change(previous.body, revision.body)
    ]
    |> Enum.reject(&(&1 in [false, nil]))
  end

  defp humanize_changes([]), do: "Saved the revision without changing the proposal text."

  defp humanize_changes(changes) do
    changes
    |> join_changes()
    |> then(&(String.capitalize(&1) <> "."))
  end

  defp join_changes([change]), do: change

  defp join_changes(changes) do
    {last_change, previous_changes} = List.pop_at(changes, -1)
    "#{Enum.join(previous_changes, ", ")} and #{last_change}"
  end

  defp format_change(:renamed), do: "renamed the spec"

  defp format_change({:status_changed, previous, current}) do
    "moved the status from #{humanize_status(previous)} to #{humanize_status(current)}"
  end

  defp format_change({:body_changed, added, removed}) do
    cond do
      added > 0 and removed > 0 ->
        "updated the proposal body with #{change_count(added, "addition")} and #{change_count(removed, "removal")}"

      added > 0 ->
        "expanded the proposal body with #{change_count(added, "addition")}"

      removed > 0 ->
        "trimmed the proposal body with #{change_count(removed, "removal")}"

      true ->
        "updated the proposal body"
    end
  end

  defp body_change(previous_body, body) do
    previous_lines = meaningful_lines(previous_body)
    lines = meaningful_lines(body)

    diff = List.myers_difference(previous_lines, lines)
    added = diff |> Keyword.get_values(:ins) |> List.flatten() |> length()
    removed = diff |> Keyword.get_values(:del) |> List.flatten() |> length()

    {:body_changed, added, removed}
  end

  defp meaningful_lines(nil), do: []

  defp meaningful_lines(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp change_count(1, label), do: "1 #{label}"
  defp change_count(count, label), do: "#{count} #{label}s"

  defp humanize_status(status) when is_atom(status),
    do: status |> Atom.to_string() |> String.replace("_", " ")

  defp humanize_status(status), do: to_string(status)
end
