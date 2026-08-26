defmodule Hive.MCP.Components.Tools.ListInferenceProfiles do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_inference_profiles",
    title: "List Inference Profiles",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "Search profile names, descriptions, providers, or upstream models."
        },
        "enabled" => %{
          "type" => "boolean",
          "description" => "Restrict to enabled or disabled profiles."
        },
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "profiles" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.inference_profile()
          },
          "pagination" => Hive.MCP.Components.Schemas.pagination()
        },
        ["profiles", "pagination"]
      )

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.Inference, as: InferenceTool
  alias Hive.Ops.Policy

  @impl EMCP.Tool
  def description, do: "List inference profiles and their pricing. Only available to admins."

  @impl EMCP.Tool
  def call(conn, args) do
    if Policy.authorize?(:inference_profile_manage, conn.assigns[:current_user], nil) do
      {profiles, meta} = Inference.list_profiles(list_opts(args))

      json_response(%{
        profiles: Enum.map(profiles, &InferenceTool.profile_json/1),
        pagination: InferenceTool.pagination_json(meta)
      })
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp list_opts(args) do
    [
      query: present(args["query"]),
      enabled: boolean(args["enabled"]),
      page: positive_integer(args["page"], 1),
      page_size: min(positive_integer(args["page_size"], 20), 100)
    ]
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
  defp boolean(value) when is_boolean(value), do: value
  defp boolean(_value), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp present(_value), do: nil
end
