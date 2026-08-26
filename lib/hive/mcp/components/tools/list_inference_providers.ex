defmodule Hive.MCP.Components.Tools.ListInferenceProviders do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "list_inference_providers",
    title: "List Inference Providers",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "providers" => %{
            "type" => "array",
            "items" => Hive.MCP.Components.Schemas.inference_provider()
          }
        },
        ["providers"]
      )

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.Inference, as: InferenceTool
  alias Hive.Ops.Policy

  @impl EMCP.Tool
  def description do
    "List inference provider endpoints and configuration status without credentials. Only available to admins."
  end

  @impl EMCP.Tool
  def call(conn, _args) do
    if Policy.authorize?(:inference_profile_manage, conn.assigns[:current_user], nil) do
      json_response(%{
        providers: Enum.map(Inference.list_provider_configs(), &InferenceTool.provider_json/1)
      })
    else
      json_response(%{error: "forbidden"})
    end
  end
end
