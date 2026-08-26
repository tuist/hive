defmodule Hive.MCP.Components.Tools.ListInferenceProvidersTest do
  use Hive.MCPToolCase

  alias Hive.Inference
  alias Hive.MCP.Components.Tools.ListInferenceProviders

  test "lists provider configuration without credentials for admins" do
    admin = mcp_user("inference-provider-admin@example.com", :admin)
    provider_key = "provider-#{System.unique_integer([:positive])}"
    credential = "provider-token-test"

    {:ok, _provider} =
      Inference.create_provider(%{
        key: provider_key,
        base_url: "https://provider.example.com/v1",
        api_key: credential,
        timeout: 120_000
      })

    response = ListInferenceProviders.call(mcp_conn(admin), %{})
    data = response_json(response)

    assert provider = Enum.find(data["providers"], &(&1["id"] == provider_key))
    assert provider["credential_configured"]
    assert provider["source"] == "database"
    assert provider["timeout"] == 120_000
    refute response |> inspect() =~ credential
  end

  test "rejects non-admin users" do
    response = mcp_user() |> mcp_conn() |> ListInferenceProviders.call(%{}) |> response_json()

    assert response == %{"error" => "forbidden"}
  end
end
