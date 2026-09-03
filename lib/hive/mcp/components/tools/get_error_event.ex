defmodule Hive.MCP.Components.Tools.GetErrorEvent do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "get_error_event",
    title: "Get Error Event",
    schema: %{
      "type" => "object",
      "required" => ["issue_id", "event_id"],
      "properties" => %{
        "issue_id" => %{"type" => "string", "description" => "Issue the event belongs to."},
        "event_id" => %{
          "type" => "string",
          "description" =>
            "Event identifier, either the canonical UUID form or the 32-character hex form."
        }
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{"event" => Hive.MCP.Components.Schemas.error_event()},
        ["event"]
      )

  alias Hive.Errors
  alias Hive.Errors.Policy

  @impl EMCP.Tool
  def description,
    do:
      "Fetch a single captured event by issue and event id. Requires ClickHouse and organization membership."

  @impl EMCP.Tool
  def call(conn, %{"issue_id" => issue_id, "event_id" => event_id}) do
    user = conn.assigns[:current_user]

    cond do
      not Policy.authorize?(:error_issue_read, user, nil) ->
        json_response(%{error: "forbidden"})

      not Errors.enabled?() ->
        json_response(%{error: "clickhouse_disabled"})

      true ->
        case Errors.fetch_event(issue_id, event_id) do
          nil -> json_response(%{error: "not_found"})
          event -> json_response(%{event: serialize(event)})
        end
    end
  end

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
end
