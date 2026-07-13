defmodule Hive.Specs.RevisionSummaries do
  @moduledoc """
  Builds the input for the revision summary agent and stores its output
  on the revision so the spec history shows what actually changed.
  """

  import Ecto.Query

  alias Hive.Agents.Sessions
  alias Hive.Repo
  alias Hive.Specs
  alias Hive.Specs.Agents.RevisionSummaryAgent
  alias Hive.Specs.Revision

  @max_body_length 8_000

  @doc """
  Generates and persists the summary for the given revision id.

  Returns `:skipped` when there is no previous revision to diff against
  (the very first draft) or when the LLM is not configured.
  """
  def summarize(revision_id, opts \\ []) when is_binary(revision_id) do
    case Repo.get(Revision, revision_id) do
      nil -> {:error, :not_found}
      revision -> summarize_revision(revision, opts)
    end
  end

  def summarize_revision(%Revision{} = revision, opts \\ []) do
    case fetch_previous(revision) do
      nil ->
        :skipped

      %Revision{} = previous ->
        runner = Keyword.get(opts, :runner, &run_agent(&1, opts))
        input = build_input(previous, revision)

        input
        |> runner.()
        |> handle_agent_result(revision)
    end
  end

  def build_input(%Revision{} = previous, %Revision{} = current) do
    %{
      previous: %{
        title: previous.title,
        status: Atom.to_string(previous.status)
      },
      current: %{
        title: current.title,
        status: Atom.to_string(current.status)
      },
      body_diff: body_diff(previous.body, current.body)
    }
  end

  defp fetch_previous(%Revision{spec_id: spec_id, revision: revision}) when revision > 1 do
    Revision
    |> where([r], r.spec_id == ^spec_id and r.revision == ^(revision - 1))
    |> Repo.one()
  end

  defp fetch_previous(_revision), do: nil

  defp run_agent(input, opts) do
    agent = Keyword.get(opts, :agent, RevisionSummaryAgent)

    agent_opts =
      opts
      |> Keyword.get(:agent_opts, [])
      |> Keyword.put_new(:load_project_instructions, false)
      |> Keyword.put_new(:max_turns, 1)

    Sessions.run(agent, summary_prompt(input), agent_opts)
  end

  defp handle_agent_result(result, revision) do
    case result do
      {:ok, %{summary: summary}} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, %{"summary" => summary}} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, summary} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, _other} ->
        {:error, :invalid_agent_response}

      {:error, :llm_not_configured} ->
        :skipped

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp summary_prompt(input) do
    """
    Compare the previous and current revisions and return only the revision
    summary text. Do not wrap the summary in structured data or Markdown.

    Previous title: #{input.previous.title}
    Previous status: #{input.previous.status}
    Current title: #{input.current.title}
    Current status: #{input.current.status}

    Body diff:
    ```diff
    #{input.body_diff}
    ```
    """
  end

  defp store_summary(revision, summary) do
    revision
    |> Revision.summary_changeset(normalize_summary(summary))
    |> Repo.update()
    |> case do
      {:ok, revision} ->
        Specs.broadcast_revision_summary_updated(revision)
        {:ok, revision}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp normalize_summary(summary) do
    summary
    |> String.trim()
    |> String.replace(~r/\A```(?:text|markdown)?\s*/i, "")
    |> String.replace(~r/\s*```\z/, "")
    |> String.trim()
    |> String.slice(0, 500)
  end

  defp truncate(value) when is_binary(value) do
    if String.length(value) > @max_body_length,
      do: String.slice(value, 0, @max_body_length) <> "...",
      else: value
  end

  defp truncate(_value), do: ""

  defp body_diff(previous, current) do
    previous = previous |> truncate() |> String.split("\n")
    current = current |> truncate() |> String.split("\n")

    previous
    |> List.myers_difference(current)
    |> Enum.map_join("\n", &format_diff_part/1)
  end

  defp format_diff_part({:del, lines}), do: Enum.map_join(lines, "\n", &("- " <> &1))
  defp format_diff_part({:ins, lines}), do: Enum.map_join(lines, "\n", &("+ " <> &1))

  defp format_diff_part({:eq, lines}) when length(lines) <= 6,
    do: Enum.map_join(lines, "\n", &("  " <> &1))

  defp format_diff_part({:eq, lines}) do
    omitted = length(lines) - 6

    (Enum.take(lines, 3) ++ ["… #{omitted} unchanged lines …"] ++ Enum.take(lines, -3))
    |> Enum.map_join("\n", &("  " <> &1))
  end
end
