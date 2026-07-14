defmodule Hive.MCP.Components.Tools.DropDigests do
  @moduledoc """
  Shared JavaScript Object Notation projections for weekly Drops digests.
  """

  alias Hive.Drops.WeeklyDigests

  def digest_schema do
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

  def digest_json(digest) do
    %{
      id: digest.id,
      week_start: Date.to_iso8601(digest.week_start),
      week_end: Date.to_iso8601(digest.week_end),
      title: digest.title,
      summary: digest.summary,
      body: digest.body,
      drop_count: length(digest.drop_ids),
      hive_url: WeeklyDigests.public_path(digest),
      published_at: DateTime.to_iso8601(digest.published_at)
    }
  end
end
