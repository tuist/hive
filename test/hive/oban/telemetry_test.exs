defmodule Hive.Oban.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Hive.Oban.Telemetry

  test "defines duration, queue time, and count metrics for job outcomes" do
    metrics = Telemetry.metrics()

    assert Enum.map(metrics, &Enum.join(&1.name, ".")) == [
             "oban.job.stop.count",
             "oban.job.stop.duration",
             "oban.job.stop.queue_time",
             "oban.job.exception.count",
             "oban.job.exception.duration",
             "oban.job.exception.queue_time"
           ]

    assert Enum.all?(metrics, &(&1.tags == [:worker, :queue, :state]))

    metric = hd(metrics)
    job = %Oban.Job{worker: "Hive.Worker", queue: "default"}

    assert metric.tag_values.(%{job: job, state: :success}) == %{
             worker: "Hive.Worker",
             queue: "default",
             state: "success"
           }
  end

  test "logs failed jobs without exposing their arguments" do
    job = %Oban.Job{
      id: 123,
      worker: "Hive.Worker",
      queue: "default",
      args: %{"token" => "sensitive"},
      attempt: 2,
      max_attempts: 3
    }

    log =
      capture_log(fn ->
        Telemetry.handle_event(
          [:oban, :job, :exception],
          %{duration: System.convert_time_unit(25, :millisecond, :native), queue_time: 0},
          %{
            job: job,
            state: :failure,
            kind: :error,
            reason: %RuntimeError{message: "also sensitive"}
          },
          nil
        )
      end)

    assert log =~ "background_job_failed"
    assert log =~ "Hive.Worker"
    assert log =~ "job_id: 123"
    assert log =~ "duration_ms: 25"
    refute log =~ "sensitive"
  end
end
