defmodule Hive.MCP.Components.Tools.ListAuditActivities do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_audit_activities",
    title: "List Audit Activities",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search actor, action, target, or metadata."
        },
        "interface" => %{
          "type" => "string",
          "enum" => Hive.Audit.interfaces(),
          "description" => "Filter by the interface that originated the activity."
        },
        "actor_kind" => %{
          "type" => "string",
          "enum" => Hive.Audit.actor_kinds(),
          "description" => "Filter by actor kind: user, agent, or system."
        },
        "action" => %{
          "type" => "string",
          "description" => "Filter by exact action name, e.g. spec.updated."
        },
        "actor_email" => %{"type" => "string", "description" => "Filter by exact actor email."},
        "target_type" => %{
          "type" => "string",
          "description" => "Filter by target type, e.g. spec."
        },
        "target_id" => %{"type" => "string", "description" => "Filter by exact target id."},
        "occurred_after" => %{
          "type" => "string",
          "description" => "Inclusive ISO-8601 date or datetime lower bound."
        },
        "occurred_before" => %{
          "type" => "string",
          "description" => "Inclusive ISO-8601 date or datetime upper bound."
        },
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "activities" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Tools.Audit.activity_schema()
          },
          "pagination" => Hive.MCP.Components.Tools.Audit.pagination_schema()
        },
        ["activities", "pagination"]
      )

  alias Hive.Audit
  alias Hive.Audit.Policy

  @impl EMCP.Tool
  def description, do: "List Hive audit activities. Only available to admins."

  @impl EMCP.Tool
  def call(conn, args) do
    user = conn.assigns[:current_user]

    if Policy.authorize?(:audit_activity_read, user, nil) do
      {activities, meta} =
        args
        |> list_opts()
        |> Audit.list_activities()

      json_response(%{
        activities: Enum.map(activities, &Audit.serialize/1),
        pagination: meta
      })
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp list_opts(args) do
    [
      page: page(args),
      page_size: page_size(args),
      query: present(args, "query"),
      interface: present(args, "interface"),
      actor_kind: present(args, "actor_kind"),
      action: present(args, "action"),
      actor_email: present(args, "actor_email"),
      target_type: present(args, "target_type"),
      target_id: present(args, "target_id"),
      occurred_after: present(args, "occurred_after"),
      occurred_before: present(args, "occurred_before")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp page(%{"page" => page}) when is_integer(page) and page > 0, do: page
  defp page(_args), do: 1

  defp page_size(%{"page_size" => size}) when is_integer(size) and size > 0, do: min(size, 100)
  defp page_size(_args), do: 25

  defp present(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _value ->
        nil
    end
  end
end
