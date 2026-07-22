defmodule Hive.Notifications.DispatcherWorker do
  @moduledoc """
  Fans durable notification events out into per-user email deliveries.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :queue], period: :infinity, states: :incomplete]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Hive.Notifications.dispatch_pending()
  end
end
