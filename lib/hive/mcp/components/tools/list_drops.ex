defmodule Hive.MCP.Components.Tools.ListDrops do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_drops",
    title: "List Drops",
    schema: %{
      "type" => "object",
      "properties" => %{
        "meadow_id" => %{
          "type" => "string",
          "description" => "Restrict to a single meadow id."
        },
        "source_type" => %{
          "type" => "string",
          "enum" => ["github_release", "rss"],
          "description" => "Restrict to a source type."
        },
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    }

  alias Hive.Drops
  alias Hive.MCP.Components.Tools.Drops, as: DropTool
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description,
    do: "List shipped-update drops, optionally filtered by meadow or source type."

  @impl EMCP.Tool
  def call(conn, args) do
    user = conn.assigns[:current_user]
    page = Map.get(args, "page", 1)
    page_size = Map.get(args, "page_size", 20)

    opts =
      [user: user, page: page, page_size: page_size]
      |> put_present(:meadow_ids, wrap(args["meadow_id"]))
      |> put_present(:source_type, parse_source_type(args["source_type"]))

    {drops, meta} = Drops.list_drops(opts)

    Tool.json_response(%{
      drops: Enum.map(drops, &DropTool.drop_json/1),
      meta: %{
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_entries: meta.total_entries,
        total_pages: meta.total_pages
      }
    })
  end

  defp parse_source_type("github_release"), do: :github_release
  defp parse_source_type("rss"), do: :rss
  defp parse_source_type(_other), do: nil

  defp wrap(nil), do: nil
  defp wrap(""), do: nil
  defp wrap(value) when is_binary(value), do: [value]

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)
end
