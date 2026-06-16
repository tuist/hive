defmodule Hive.Meadows.EvolutionWorker do
  @moduledoc """
  Evolves the meadow taxonomy from recent work signals.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [
      fields: [:worker, :queue],
      period: :infinity,
      states: :incomplete
    ]

  require Logger

  @default_debounce_seconds 30

  @doc """
  Enqueues a debounced evolution job when agentic workflows are enabled.
  """
  def enqueue(opts \\ []) do
    agents_enabled? = Keyword.get(opts, :agents_enabled?, &Hive.Agents.enabled?/0)
    schedule_in = Keyword.get(opts, :schedule_in, @default_debounce_seconds)

    if agents_enabled?.() do
      %{}
      |> new(schedule_in: schedule_in)
      |> Oban.insert()
    else
      :skipped
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Hive.Meadows.evolve_from_work_items() do
      {:ok, %{created: created, updated: updated, skipped: skipped}} ->
        Logger.info(
          "[Meadows.EvolutionWorker] Evolution finished: #{length(created)} created, " <>
            "#{length(updated)} updated, #{length(skipped)} skipped"
        )

        :ok

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_evolution_result, other}}
    end
  end
end
