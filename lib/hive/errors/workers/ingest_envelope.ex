defmodule Hive.Errors.Workers.IngestEnvelope do
  @moduledoc """
  Parses a Sentry envelope and records every "event" item it contains.
  Non-event items (transactions, sessions, attachments, replays,
  check-ins, profiles, feedback, ...) are politely dropped: the
  ingest endpoint has already returned 200 to the SDK, and per the
  Sentry protocol we must not have the SDK retry them.
  """

  use Oban.Worker,
    queue: :errors,
    max_attempts: 5

  require Logger

  alias Hive.Errors
  alias Hive.Errors.Envelope
  alias Hive.Errors.SentryEvent
  alias Hive.Projects.Project
  alias Hive.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "body" => body}}) do
    with %Project{} = project <- Repo.get(Project, project_id),
         {:ok, envelope} <- Envelope.parse(body) do
      envelope.items
      |> Enum.filter(&(&1.type == "event"))
      |> Enum.reduce_while(:ok, fn item, _acc ->
        case ingest_item(project, item) do
          :ok -> {:cont, :ok}
          {:error, :not_configured} -> {:halt, {:cancel, :not_configured}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> normalize_result()
    else
      nil ->
        {:cancel, :project_not_found}

      {:error, reason} ->
        Logger.warning("errors: dropping malformed envelope: #{inspect(reason)}")
        {:cancel, reason}
    end
  end

  defp ingest_item(project, item) do
    with {:ok, decoded} <- Jason.decode(item.payload),
         event = SentryEvent.parse(decoded),
         {:ok, _issue} <- Errors.record_event(project, event) do
      :ok
    else
      {:error, %Jason.DecodeError{}} -> :ok
      other -> other
    end
  end

  defp normalize_result(:ok), do: :ok
  defp normalize_result({:cancel, _} = cancel), do: cancel
  defp normalize_result({:error, _} = err), do: err
end
