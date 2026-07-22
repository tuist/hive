defmodule Hive.Notifications.DeliveryWorker do
  @moduledoc """
  Delivers immediate notification email or a due daily summary.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  alias Hive.Notifications
  alias Hive.Notifications.Delivery
  alias Hive.Notifications.Email

  def enqueue(%Delivery{cadence: :immediate, id: id, scheduled_at: scheduled_at}) do
    %{"delivery_id" => id, "cadence" => "immediate"}
    |> new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  def enqueue(%Delivery{cadence: :daily} = delivery) do
    %{
      "cadence" => "daily",
      "user_id" => delivery.user_id,
      "topic" => Atom.to_string(delivery.topic),
      "scheduled_at" => DateTime.to_iso8601(delivery.scheduled_at)
    }
    |> new(scheduled_at: delivery.scheduled_at)
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    run(job)
  rescue
    error ->
      mark_terminal_failure(job, error)
      reraise error, __STACKTRACE__
  end

  defp run(%Oban.Job{args: %{"delivery_id" => delivery_id, "cadence" => "immediate"}} = job) do
    delivery = Notifications.get_delivery(delivery_id)

    result =
      case delivery do
        %Delivery{status: :pending, cadence: :immediate} ->
          Email.deliver_immediate(delivery)

        _missing_or_finished ->
          :ok
      end

    finish(result, delivery, job)
  end

  defp run(
         %Oban.Job{
           args: %{"user_id" => user_id, "topic" => topic, "cadence" => "daily"}
         } = job
       ) do
    delivery = Notifications.get_due_daily_delivery(user_id, topic)
    result = if delivery, do: Email.deliver_daily(delivery), else: :ok
    deliveries = if delivery, do: Notifications.due_daily_deliveries(delivery), else: []
    finish(result, deliveries, job)
  end

  defp finish(result, delivery, job) do
    case result do
      {:error, reason} when job.attempt >= job.max_attempts ->
        Notifications.mark_failed(delivery, reason, terminal: true)
        {:error, reason}

      other ->
        other
    end
  end

  # A delivery that raises instead of returning an error would otherwise stay
  # pending forever and be re-enqueued on every sweep. Recording the terminal
  # failure must not mask the original error, so a failure to record it is left
  # to the next attempt.
  defp mark_terminal_failure(%Oban.Job{} = job, error) do
    if job.attempt >= job.max_attempts do
      job
      |> exhausted_deliveries()
      |> Notifications.mark_failed(error, terminal: true)
    end
  rescue
    _error -> :ok
  end

  defp exhausted_deliveries(%Oban.Job{args: %{"delivery_id" => delivery_id}}) do
    delivery_id |> Notifications.get_delivery() |> List.wrap()
  end

  defp exhausted_deliveries(%Oban.Job{args: %{"user_id" => user_id, "topic" => topic}}) do
    case Notifications.get_due_daily_delivery(user_id, topic) do
      nil -> []
      delivery -> Notifications.due_daily_deliveries(delivery)
    end
  end

  defp exhausted_deliveries(%Oban.Job{}), do: []
end
