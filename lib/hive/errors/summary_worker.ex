defmodule Hive.Errors.SummaryWorker do
  @moduledoc """
  Reconciles the current error-summary reporting period and delivers it to
  Slack when the runtime configuration enables the workflow.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  require Logger

  alias Hive.Agents.Errors
  alias Hive.Audit
  alias Hive.Errors.Summaries

  @provider_snooze_seconds 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    Audit.put_context(%{interface: "worker"})

    scheduled_for =
      (job.inserted_at || DateTime.utc_now())
      |> DateTime.to_unix()
      |> then(&(div(&1, 60) * 60))
      |> DateTime.from_unix!()

    case Summaries.run(retry?: job.attempt > 1, scheduled_for: scheduled_for) do
      {:ok, run, :delivered} ->
        Audit.record("error.summary.posted", %{
          target_type: "error_summary",
          target_id: run.id,
          target_label: "Error summary",
          metadata: %{
            issue_count: run.issue_count,
            path: "/errors",
            slack_channel_id: run.slack_channel_id
          }
        })

        :ok

      {:ok, _run, _outcome} ->
        :ok

      {:error, reason} ->
        handle_error(reason)
    end
  rescue
    error in [ReqLLM.Error.API.Request, ReqLLM.Error.API.Response] -> handle_error(error)
  end

  defp handle_error(reason) do
    sanitized = Errors.sanitize_reason(reason, :error_summary_failed)

    cond do
      hard_reason = Errors.hard_failure_reason(reason) ->
        Logger.warning(
          "[Errors.SummaryWorker] Model provider or Slack rejected the summary: " <>
            inspect(sanitized)
        )

        {:cancel, hard_reason}

      Errors.provider_unavailable?(reason) ->
        Logger.warning("[Errors.SummaryWorker] Model provider unavailable: #{inspect(sanitized)}")

        {:snooze, @provider_snooze_seconds}

      true ->
        Logger.warning("[Errors.SummaryWorker] Summary failed: #{inspect(sanitized)}")
        {:error, sanitized}
    end
  end
end
