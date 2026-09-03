defmodule Hive.MCP.Components.Tools.ListErrorEvents do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_error_events",
    title: "List Error Events",
    schema: %{
      "type" => "object",
      "required" => ["issue_id"],
      "properties" => %{
        "issue_id" => %{"type" => "string", "description" => "Issue id."},
        "from" => %{
          "type" => "string",
          "description" => "Inclusive ISO 8601 lower bound on the event timestamp."
        },
        "to" => %{
          "type" => "string",
          "description" => "Inclusive ISO 8601 upper bound on the event timestamp."
        },
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 200}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "events" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.error_event()
          }
        },
        ["events"]
      )

  alias Hive.Errors
  alias Hive.Errors.Policy

  @impl EMCP.Tool
  def description,
    do:
      "List captured events for an issue, ordered newest first. Requires ClickHouse and organization membership."

  @impl EMCP.Tool
  def call(conn, %{"issue_id" => issue_id} = args) do
    user = conn.assigns[:current_user]

    cond do
      not Policy.authorize?(:error_issue_read, user, nil) ->
        json_response(%{error: "forbidden"})

      not Errors.enabled?() ->
        json_response(%{error: "clickhouse_disabled"})

      true ->
        opts = event_opts(args)
        events = Errors.list_events_for_issue(issue_id, opts) |> Enum.map(&serialize/1)
        json_response(%{events: events})
    end
  end

  defp event_opts(args) do
    [
      limit: limit(args),
      from: parse_datetime(args, "from"),
      to: parse_datetime(args, "to")
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp limit(%{"limit" => n}) when is_integer(n) and n > 0, do: min(n, 200)
  defp limit(_), do: 25

  defp serialize(event) do
    %{
      event_id: to_string(event.event_id),
      timestamp: format_timestamp(event.timestamp),
      level: to_string(event.level),
      environment: to_string(event.environment),
      release: to_string(event.release),
      exception_type: to_string(event.exception_type),
      exception_value: to_string(event.exception_value),
      top_frame_function: to_string(event.top_frame_function),
      top_frame_filename: to_string(event.top_frame_filename),
      payload: event.payload
    }
  end

  defp format_timestamp(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_timestamp(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_timestamp(nil), do: nil
  defp format_timestamp(other), do: to_string(other)

  defp parse_datetime(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _offset} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
