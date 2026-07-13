defmodule Hive.Drops.WeeklyDigestWorker do
  @moduledoc """
  Generates the latest publishable Monday-to-Friday Drops digest once.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  require Logger

  alias Hive.Agents.Errors
  alias Hive.Audit
  alias Hive.Drops.WeeklyDigests

  @claim_snooze_seconds 300
  @provider_snooze_seconds 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Audit.put_context(%{interface: "worker"})

    case WeeklyDigests.generate_latest_week() do
      {:ok, digest, :published} ->
        Audit.record(:"drop.weekly_digest.generated", %{
          target_type: "drop_digest",
          target_id: digest.id,
          target_label: digest.title,
          metadata: %{week_start: Date.to_iso8601(digest.week_start)}
        })

        :ok

      {:ok, _digest, :busy} ->
        {:snooze, @claim_snooze_seconds}

      {:ok, _digest, _outcome} ->
        :ok

      :skipped ->
        :ok

      {:error, reason} ->
        handle_error(reason)
    end
  rescue
    error in [ReqLLM.Error.API.Request, ReqLLM.Error.API.Response] -> handle_error(error)
  end

  defp handle_error(reason) do
    sanitized = Errors.sanitize_reason(reason, :weekly_digest_generation_failed)

    cond do
      hard_reason = Errors.hard_failure_reason(reason) ->
        Logger.warning(
          "[Drops.WeeklyDigestWorker] Model provider rejected generation: #{inspect(sanitized)}"
        )

        {:cancel, hard_reason}

      Errors.provider_unavailable?(reason) ->
        Logger.warning(
          "[Drops.WeeklyDigestWorker] Model provider unavailable: #{inspect(sanitized)}"
        )

        {:snooze, @provider_snooze_seconds}

      true ->
        Logger.warning("[Drops.WeeklyDigestWorker] Generation failed: #{inspect(sanitized)}")
        {:error, sanitized}
    end
  end
end
