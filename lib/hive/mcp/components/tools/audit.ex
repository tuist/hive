defmodule Hive.MCP.Components.Tools.Audit do
  @moduledoc """
  Shared output schema for the audit activities returned by `list_audit_activities`
  and `get_audit_activity`. The payload itself is built by `Hive.Audit.serialize/1`.
  """

  def activity_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "action" => %{"type" => "string"},
        "interface" => %{"type" => "string"},
        "occurred_at" => %{"type" => ["string", "null"]},
        "actor" => %{
          "type" => "object",
          "properties" => %{
            "kind" => %{"type" => "string"},
            "id" => %{"type" => ["string", "null"]},
            "email" => %{"type" => ["string", "null"]},
            "name" => %{"type" => ["string", "null"]},
            "role" => %{"type" => ["string", "null"]}
          },
          "required" => ["kind", "id", "email", "name", "role"],
          "additionalProperties" => false
        },
        "target" => %{
          "type" => "object",
          "properties" => %{
            "type" => %{"type" => ["string", "null"]},
            "id" => %{"type" => ["string", "null"]},
            "label" => %{"type" => ["string", "null"]},
            "path" => %{"type" => ["string", "null"]}
          },
          "required" => ["type", "id", "label", "path"],
          "additionalProperties" => false
        },
        "metadata" => %{"type" => "object"}
      },
      "required" => ["id", "action", "interface", "occurred_at", "actor", "target", "metadata"],
      "additionalProperties" => false
    }
  end

  def pagination_schema do
    %{
      "type" => "object",
      "properties" => %{
        "current_page" => %{"type" => "integer"},
        "page_size" => %{"type" => "integer"},
        "total_count" => %{"type" => "integer"},
        "total_pages" => %{"type" => "integer"},
        "has_next_page?" => %{"type" => "boolean"},
        "has_previous_page?" => %{"type" => "boolean"}
      },
      "required" => [
        "current_page",
        "page_size",
        "total_count",
        "total_pages",
        "has_next_page?",
        "has_previous_page?"
      ],
      "additionalProperties" => false
    }
  end
end
