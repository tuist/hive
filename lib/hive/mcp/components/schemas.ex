defmodule Hive.MCP.Components.Schemas do
  @moduledoc false

  def project do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "visibility" => %{"type" => "string"},
        "domains" => %{"type" => "array", "items" => domain_summary()},
        "repositories" => %{"type" => "array", "items" => repository()},
        "webhooks" => %{"type" => "array", "items" => webhook()},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "name",
        "description",
        "visibility",
        "domains",
        "repositories",
        "webhooks",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def domain do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "visibility" => %{"type" => "string"},
        "projects" => %{"type" => "array", "items" => project_summary()},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "name",
        "description",
        "visibility",
        "projects",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def spec do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "number" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => ["string", "null"]},
        "summary" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "visibility" => %{"type" => "string"},
        "visibility_override" => %{"type" => ["string", "null"]},
        "effective_visibility" => %{"type" => "string"},
        "revision" => %{"type" => "integer"},
        "project" => nullable_project(),
        "domains" => %{"type" => "array", "items" => spec_domain()},
        "source_forage_item" => nullable_forage_item(),
        "comments" => %{"type" => "array", "items" => comment()},
        "revisions" => %{"type" => "array", "items" => revision()},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "number",
        "title",
        "body",
        "summary",
        "status",
        "visibility",
        "visibility_override",
        "effective_visibility",
        "revision",
        "project",
        "domains",
        "source_forage_item",
        "comments",
        "revisions",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def postmortem do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "number" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "visibility" => %{"type" => "string"},
        "author" => nullable_postmortem_author(),
        "domains" => %{"type" => "array", "items" => postmortem_domain()},
        "action_items" => %{"type" => "array", "items" => postmortem_action_item()},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"},
        "path" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "number",
        "title",
        "body",
        "visibility",
        "author",
        "domains",
        "action_items",
        "inserted_at",
        "updated_at",
        "path"
      ],
      "additionalProperties" => false
    }
  end

  def postmortem_action_item do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "postmortem_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "completed" => %{"type" => "boolean"},
        "completed_at" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "postmortem_id",
        "title",
        "description",
        "completed",
        "completed_at",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def comment do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "author" => %{"type" => "string"},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => ["id", "body", "author", "inserted_at", "updated_at"],
      "additionalProperties" => false
    }
  end

  defp nullable_postmortem_author do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "email" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "email", "name"],
      "additionalProperties" => false
    }
  end

  defp postmortem_domain do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "visibility" => %{"type" => "string"}
      },
      "required" => ["id", "name", "visibility"],
      "additionalProperties" => false
    }
  end

  def flight do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "objective" => %{"type" => "string"},
        "objective_outcome" => %{"type" => ["string", "null"]},
        "runner" => %{"type" => "string"},
        "runner_id" => %{"type" => ["string", "null"]},
        "repository" => %{"type" => "string"},
        "forage_item" => nullable_flight_forage_item(),
        "input" => %{"type" => "object", "additionalProperties" => true},
        "trigger" => %{"type" => "object", "additionalProperties" => true},
        "session" => %{"type" => ["object", "null"], "additionalProperties" => true},
        "result" => %{"type" => ["object", "null"], "additionalProperties" => true},
        "error" => %{"type" => ["string", "null"]},
        "requested_by" => nullable_flight_requester(),
        "parent_flight_id" => %{"type" => ["string", "null"]},
        "started_at" => %{"type" => ["string", "null"]},
        "completed_at" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"},
        "path" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "status",
        "objective",
        "objective_outcome",
        "runner",
        "runner_id",
        "repository",
        "forage_item",
        "input",
        "trigger",
        "session",
        "result",
        "error",
        "requested_by",
        "parent_flight_id",
        "started_at",
        "completed_at",
        "inserted_at",
        "updated_at",
        "path"
      ],
      "additionalProperties" => false
    }
  end

  defp nullable_flight_forage_item do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "type" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "path" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "type", "title", "status", "path"],
      "additionalProperties" => false
    }
  end

  defp nullable_flight_requester do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "email" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "email", "name"],
      "additionalProperties" => false
    }
  end

  def drop do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "number" => %{"type" => "integer"},
        "projects" => %{"type" => "array", "items" => named_reference()},
        "domains" => %{"type" => "array", "items" => named_reference()},
        "classified_at" => %{"type" => ["string", "null"]},
        "source_type" => %{"type" => "string"},
        "source_label" => %{"type" => "string"},
        "external_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => ["string", "null"]},
        "url" => %{"type" => ["string", "null"]},
        "hive_url" => %{"type" => "string"},
        "version" => %{"type" => ["string", "null"]},
        "repository" => %{"type" => ["string", "null"]},
        "github_issues" => %{"type" => "array", "items" => github_issue()},
        "published_at" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "number",
        "projects",
        "domains",
        "classified_at",
        "source_type",
        "source_label",
        "external_id",
        "title",
        "body",
        "url",
        "hive_url",
        "version",
        "repository",
        "github_issues",
        "published_at",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def drop_digest do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "week_start" => %{"type" => "string"},
        "week_end" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "summary" => %{"type" => "string"},
        "body" => %{"type" => "string"},
        "drop_count" => %{"type" => "integer"},
        "hive_url" => %{"type" => "string"},
        "published_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "week_start",
        "week_end",
        "title",
        "summary",
        "body",
        "drop_count",
        "hive_url",
        "published_at"
      ],
      "additionalProperties" => false
    }
  end

  def audit_activity do
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

  def pagination do
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

  def repository do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "owner" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "full_name" => %{"type" => "string"},
        "visibility" => %{"type" => "string"},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "owner",
        "name",
        "full_name",
        "visibility",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def webhook do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "source" => %{"type" => "string"},
        "source_label" => %{"type" => "string"},
        "last_used_at" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "name",
        "source",
        "source_label",
        "last_used_at",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  defp domain_summary do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "visibility" => %{"type" => "string"}
      },
      "required" => ["id", "name", "description", "visibility"],
      "additionalProperties" => false
    }
  end

  defp project_summary do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "description" => %{"type" => ["string", "null"]},
        "visibility" => %{"type" => "string"},
        "repositories" => %{"type" => "array", "items" => repository()}
      },
      "required" => ["id", "name", "description", "visibility", "repositories"],
      "additionalProperties" => false
    }
  end

  defp nullable_project do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "visibility" => %{"type" => "string"}
      },
      "required" => ["id", "name", "visibility"],
      "additionalProperties" => false
    }
  end

  defp spec_domain do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "visibility" => %{"type" => "string"}
      },
      "required" => ["id", "name", "visibility"],
      "additionalProperties" => false
    }
  end

  defp nullable_forage_item do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "type" => %{"type" => "string"},
        "id" => %{"type" => "string"},
        "title" => %{"type" => "string"}
      },
      "required" => ["type", "id", "title"],
      "additionalProperties" => false
    }
  end

  defp revision do
    %{
      "type" => "object",
      "properties" => %{
        "revision" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "author" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"}
      },
      "required" => ["revision", "title", "body", "status", "author", "inserted_at"],
      "additionalProperties" => false
    }
  end

  defp named_reference do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"}
      },
      "required" => ["id", "name"],
      "additionalProperties" => false
    }
  end

  defp github_issue do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "number" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "state" => %{"type" => "string"},
        "url" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "number", "title", "state", "url"],
      "additionalProperties" => false
    }
  end
end
