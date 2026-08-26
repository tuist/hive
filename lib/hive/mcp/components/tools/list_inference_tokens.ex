defmodule Hive.MCP.Components.Tools.ListInferenceTokens do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_inference_tokens",
    title: "List Inference Tokens",
    schema: %{
      "type" => "object",
      "properties" => %{
        "profile_id" => %{"type" => "string", "description" => "Restrict tokens to one profile."},
        "query" => %{"type" => "string", "description" => "Search token or profile names."},
        "enabled" => %{
          "type" => "boolean",
          "description" => "Restrict to active or revoked tokens."
        },
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "tokens" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.inference_token()
          },
          "pagination" => Hive.MCP.Components.Schemas.pagination()
        },
        ["tokens", "pagination"]
      )

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.Inference, as: InferenceTool
  alias Hive.Ops.Policy

  @impl EMCP.Tool
  def description, do: "List inference tokens without token values. Only available to admins."

  @impl EMCP.Tool
  def call(conn, args) do
    if Policy.authorize?(:inference_profile_manage, conn.assigns[:current_user], nil) do
      {tokens, meta} = Inference.list_tokens(list_opts(args))

      json_response(%{
        tokens: Enum.map(tokens, &InferenceTool.token_json/1),
        pagination: InferenceTool.pagination_json(meta)
      })
    else
      json_response(%{error: "forbidden"})
    end
  end

  defp list_opts(args) do
    [
      profile_id: present(args["profile_id"]),
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
