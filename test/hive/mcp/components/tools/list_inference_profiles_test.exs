defmodule Hive.MCP.Components.Tools.ListInferenceProfilesTest do
  use Hive.MCPToolCase

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.ListInferenceProfiles

  test "lists profiles and their pricing for admins" do
    admin = mcp_user("inference-profile-admin@example.com", :admin)

    {:ok, profile} =
      Inference.create_profile(%{
        name: profile_name("review"),
        description: "Review pull requests",
        upstream_provider: "openai",
        upstream_model: "gpt-4o-mini",
        input_cost_per_million: "0.15",
        output_cost_per_million: "0.60",
        hive_inference: true
      })

    {:ok, {_token, _value}} = Inference.create_token(profile, %{name: "Repository automation"})

    response =
      admin
      |> mcp_conn()
      |> ListInferenceProfiles.call(%{"query" => profile.name, "enabled" => true})
      |> response_json()

    assert [returned_profile] = response["profiles"]
    assert returned_profile["id"] == profile.id
    assert returned_profile["input_cost_per_million"] == "0.15"
    assert returned_profile["output_cost_per_million"] == "0.6"
    assert returned_profile["hive_inference"]
    assert returned_profile["token_count"] == 1
    assert response["pagination"]["total_count"] == 1
  end

  test "rejects non-admin users" do
    response = mcp_user() |> mcp_conn() |> ListInferenceProfiles.call(%{}) |> response_json()

    assert response == %{"error" => "forbidden"}
  end

  defp profile_name(prefix), do: unique_name(prefix) |> String.replace(" ", "-")
end
