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

        case runner.(build_input(previous, revision)) do
          {:ok, %{summary: summary}} when is_binary(summary) ->
            store_summary(revision, summary)

          {:ok, %{"summary" => summary}} when is_binary(summary) ->
            store_summary(revision, summary)

          {:ok, _other} ->
            {:error, :invalid_agent_response}

          {:error, :llm_not_configured} ->
            :skipped

          {:error, reason} ->
            {:error, reason}
        end
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

  defp store_summary(revision, summary) do
    revision
    |> Revision.summary_changeset(String.trim(summary))
    |> Repo.update()
    |> case do
      {:ok, revision} ->
        Specs.broadcast_revision_summary_updated(revision)
        {:ok, revision}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp truncate(value) when is_binary(value) do
    if String.length(value) > @max_body_length,
      do: String.slice(value, 0, @max_body_length) <> "...",
      else: value
  end

  defp truncate(_value), do: ""
end
