defmodule Hive.Drops.WeeklyDigestWorker do
  @moduledoc """
  Generates and reconciles published-week Drops digests.
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

    outcomes = WeeklyDigests.generate_publishable_weeks()

    outcomes
    |> Enum.filter(&match?({:ok, _digest, :published}, &1))
    |> Enum.each(fn {:ok, digest, :published} ->
      Audit.record(:"drop.weekly_digest.generated", %{
        target_type: "drop_digest",
        target_id: digest.id,
        target_label: digest.title,
        metadata: %{week_start: Date.to_iso8601(digest.week_start)}
      })
    end)

    cond do
      Enum.any?(outcomes, &match?({:error, _reason}, &1)) ->
        {:error, reason} = Enum.find(outcomes, &match?({:error, _reason}, &1))
        handle_error(reason)

      Enum.any?(outcomes, &match?({:ok, _digest, :busy}, &1)) ->
        {:snooze, @claim_snooze_seconds}

      true ->
        :ok
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
