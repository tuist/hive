defmodule Hive.Meadows.EvolutionWorkerTest do
  use ExUnit.Case, async: true

  alias Hive.Meadows.EvolutionWorker

  defp start_worker!(opts) do
    name = :"meadow_evolution_worker_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      start_supervised(
        {EvolutionWorker,
         Keyword.merge(
           [
             name: name,
             run_on_start: false,
             interval_ms: :timer.minutes(60),
             debounce_ms: 5
           ],
           opts
         )}
      )

    name
  end

  test "evolve_now/1 runs the configured evolution function when agents are enabled" do
    test_pid = self()

    name =
      start_worker!(
        agents_enabled?: fn -> true end,
        evolve_fun: fn ->
          send(test_pid, :evolved)
          {:ok, %{created: [], updated: [], skipped: []}}
        end
      )

    assert :ok = EvolutionWorker.evolve_now(name)
    assert_receive :evolved
  end

  test "enqueue/1 debounces evolution requests" do
    test_pid = self()

    name =
      start_worker!(
        agents_enabled?: fn -> true end,
        evolve_fun: fn ->
          send(test_pid, :evolved)
          {:ok, %{created: [], updated: [], skipped: []}}
        end
      )

    assert :ok = EvolutionWorker.enqueue(name)
    assert :ok = EvolutionWorker.enqueue(name)

    assert_receive :evolved, 100
    refute_receive :evolved, 30
  end

  test "enqueue/1 skips when the worker is not running" do
    assert :skipped = EvolutionWorker.enqueue(:missing_meadow_evolution_worker)
  end
end
