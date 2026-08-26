defmodule Hive.MCP.Components.Tools.ListInferenceTokensTest do
  use Hive.MCPToolCase

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.ListInferenceTokens

  test "lists profile tokens without token values for admins" do
    admin = mcp_user("inference-token-admin@example.com", :admin)
    profile = profile!()

    {:ok, {token, token_value}} =
      Inference.create_token(profile, %{name: "Repository automation"})

    response =
      admin
      |> mcp_conn()
      |> ListInferenceTokens.call(%{"profile_id" => profile.id})

    data = response_json(response)

    assert [returned_token] = data["tokens"]
    assert returned_token["id"] == token.id
    assert returned_token["profile"] == %{"id" => profile.id, "name" => profile.name}
    refute response |> inspect() =~ token_value
    refute Map.has_key?(returned_token, "token_hash")
    refute Map.has_key?(returned_token, "token_ciphertext")
  end

  test "rejects non-admin users" do
    response = mcp_user() |> mcp_conn() |> ListInferenceTokens.call(%{}) |> response_json()

    assert response == %{"error" => "forbidden"}
  end

  defp profile! do
    {:ok, profile} =
      Inference.create_profile(%{
        name: profile_name("profile"),
        upstream_provider: "openai",
        upstream_model: "gpt-4o-mini"
      })

    profile
  end

  defp profile_name(prefix), do: unique_name(prefix) |> String.replace(" ", "-")
end
