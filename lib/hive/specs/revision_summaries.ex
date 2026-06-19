defmodule Hive.Specs.RevisionSummaries do
  @moduledoc """
  Builds the input for the revision summary agent and stores its output
  on the revision so the spec history shows what actually changed.
  """

  import Ecto.Query

  require Logger

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
        |> handle_agent_result(revision, input, opts)
    end
  end

  def build_input(%Revision{} = previous, %Revision{} = current) do
    %{
      previous: %{
        title: previous.title,
        status: Atom.to_string(previous.status),
        body: truncate(previous.body)
      },
      current: %{
        title: current.title,
        status: Atom.to_string(current.status),
        body: truncate(current.body)
      }
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
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run_operation(agent, :summarize_revision, input, agent_opts)
  end

  defp run_freeform_agent(input, opts) do
    agent = Keyword.get(opts, :agent, RevisionSummaryAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run(agent, freeform_prompt(input), agent_opts)
  end

  defp handle_agent_result(result, revision, input, opts) do
    case result do
      {:ok, %{summary: summary}} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, %{"summary" => summary}} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, summary} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, _other} ->
        run_fallback(revision, input, :invalid_agent_response, opts)

      {:error, :llm_not_configured} ->
        :skipped

      {:error, reason} ->
        if fallback_reason?(reason),
          do: run_fallback(revision, input, reason, opts),
          else: {:error, reason}
    end
  end

  defp run_fallback(revision, input, reason, opts) do
    Logger.warning(
      "[Specs.RevisionSummaries] Structured summary failed with #{inspect(reason)}; retrying as freeform"
    )

    fallback_runner = Keyword.get(opts, :fallback_runner, &run_freeform_agent(&1, opts))

    case fallback_runner.(input) do
      {:ok, %{summary: summary}} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, %{"summary" => summary}} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, summary} when is_binary(summary) ->
        store_summary(revision, summary)

      {:ok, _other} ->
        {:error, {:fallback_failed, reason, :invalid_agent_response}}

      {:error, fallback_reason} ->
        {:error, {:fallback_failed, reason, fallback_reason}}
    end
  end

  defp fallback_reason?(:no_result_submitted), do: true
  defp fallback_reason?({:invalid_output, _reason}), do: true
  defp fallback_reason?(_reason), do: false

  defp freeform_prompt(input) do
    """
    Compare the previous and current revisions and return only the revision
    summary text. Do not wrap the summary in JSON or Markdown.

    Previous revision:
    ```json
    #{JSON.encode!(input.previous)}
    ```

    Current revision:
    ```json
    #{JSON.encode!(input.current)}
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
end
