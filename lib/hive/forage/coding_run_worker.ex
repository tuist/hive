defmodule Hive.Forage.CodingRunWorker do
  @moduledoc """
  Executes one durable Flight outside the dashboard request process.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 1,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  alias Hive.Forage.CodingRuns

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"coding_run_id" => coding_run_id}}) do
    CodingRuns.execute(coding_run_id)
  end
end
