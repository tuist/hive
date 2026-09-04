defmodule Hive.Oban.Telemetry do
  @moduledoc false

  import Telemetry.Metrics

  require Logger

  @handler_id "hive-oban-job-failures"
  @job_exception_event [:oban, :job, :exception]

  def attach do
    case :telemetry.attach(@handler_id, @job_exception_event, &handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def metrics do
    [
      counter("oban.job.stop.count",
        measurement: :duration,
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1
      ),
      summary("oban.job.stop.duration",
        unit: {:native, :millisecond},
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1
      ),
      summary("oban.job.stop.queue_time",
        unit: {:native, :millisecond},
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1
      ),
      counter("oban.job.exception.count",
        measurement: :duration,
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1
      ),
      summary("oban.job.exception.duration",
        unit: {:native, :millisecond},
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1
      ),
      summary("oban.job.exception.queue_time",
        unit: {:native, :millisecond},
        tags: [:worker, :queue, :state],
        tag_values: &job_tags/1
      )
    ]
  end

  @doc false
  def handle_event(
        @job_exception_event,
        measurements,
        %{job: %Oban.Job{} = job} = metadata,
        _config
      ) do
    Logger.error(%{
      event: "background_job_failed",
      job_id: job.id,
      worker: job.worker,
      queue: job.queue,
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      state: metadata.state,
      error_kind: metadata.kind,
      error_type: error_type(metadata.reason),
      error_message: error_message(metadata.reason),
      duration_ms: to_milliseconds(measurements.duration),
      queue_time_ms: to_milliseconds(measurements.queue_time)
    })
  end

  defp job_tags(%{job: %Oban.Job{} = job} = metadata) do
    %{
      worker: to_string(job.worker),
      queue: to_string(job.queue),
      state: metadata.state |> to_string()
    }
  end

  defp error_type(%{__struct__: module}), do: inspect(module)
  defp error_type(_reason), do: "unknown"

  # Serialize the failure reason so downstream consumers (Sentry ingest,
  # log search) see what actually failed rather than only the wrapping
  # exception's module name.
  defp error_message(reason) do
    raw =
      cond do
        is_exception(reason) -> Exception.message(reason)
        true -> inspect(reason, printable_limit: 500, limit: 50)
      end

    truncate(raw, 500)
  end

  defp truncate(nil, _max), do: nil

  defp truncate(binary, max) when is_binary(binary) and byte_size(binary) > max do
    binary_part(binary, 0, max) <> "..."
  end

  defp truncate(binary, _max) when is_binary(binary), do: binary
  defp truncate(other, _max), do: to_string(other)

  defp to_milliseconds(value),
    do: System.convert_time_unit(value, :native, :millisecond)
end
