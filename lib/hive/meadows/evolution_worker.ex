defmodule Hive.Meadows.EvolutionWorker do
  @moduledoc """
  Periodically and opportunistically evolves the meadow taxonomy.
  """

  use GenServer

  require Logger

  @default_interval_ms :timer.minutes(30)
  @default_debounce_ms :timer.seconds(30)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Enqueues a debounced evolution pass if the worker is available.
  """
  def enqueue(server \\ __MODULE__) do
    if pid = process(server) do
      GenServer.cast(pid, :enqueue)
      :ok
    else
      :skipped
    end
  end

  @doc "Runs evolution immediately. Returns when the run finishes."
  def evolve_now(server \\ __MODULE__), do: GenServer.call(server, :evolve_now, :timer.minutes(5))

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, configured(:interval_ms, @default_interval_ms))
    debounce_ms = Keyword.get(opts, :debounce_ms, configured(:debounce_ms, @default_debounce_ms))
    evolve_fun = Keyword.get(opts, :evolve_fun, &Hive.Meadows.evolve_from_work_items/0)
    agents_enabled? = Keyword.get(opts, :agents_enabled?, &Hive.Agents.enabled?/0)

    state = %{
      interval_ms: interval_ms,
      debounce_ms: debounce_ms,
      timer_ref: nil,
      evolve_fun: evolve_fun,
      agents_enabled?: agents_enabled?
    }

    if Keyword.get(opts, :run_on_start, true), do: Process.send_after(self(), :tick, 0)
    schedule_tick(interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_cast(:enqueue, state) do
    {:noreply, schedule_debounced_run(state)}
  end

  @impl true
  def handle_info(:debounced_run, state) do
    {:noreply, %{run_if_enabled(state) | timer_ref: nil}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick(state.interval_ms)
    {:noreply, run_if_enabled(state)}
  end

  @impl true
  def handle_call(:evolve_now, _from, state) do
    state = run_if_enabled(state)
    {:reply, :ok, state}
  end

  defp run_if_enabled(state) do
    if state.agents_enabled?.() do
      case state.evolve_fun.() do
        {:ok, %{created: created, updated: updated, skipped: skipped}} ->
          Logger.info(
            "[Meadows.EvolutionWorker] Evolution finished: #{length(created)} created, " <>
              "#{length(updated)} updated, #{length(skipped)} skipped"
          )

        {:error, reason} ->
          Logger.warning("[Meadows.EvolutionWorker] Evolution failed: #{inspect(reason)}")

        other ->
          Logger.warning("[Meadows.EvolutionWorker] Evolution returned #{inspect(other)}")
      end
    end

    state
  end

  defp schedule_debounced_run(%{timer_ref: nil} = state) do
    %{state | timer_ref: Process.send_after(self(), :debounced_run, state.debounce_ms)}
  end

  defp schedule_debounced_run(state), do: state

  defp schedule_tick(interval_ms), do: Process.send_after(self(), :tick, interval_ms)

  defp configured(key, default) do
    :hive
    |> Application.get_env(:meadow_evolution, [])
    |> Keyword.get(key, default)
  end

  defp process(pid) when is_pid(pid), do: pid

  defp process(name) when is_atom(name) do
    Process.whereis(name)
  end
end
