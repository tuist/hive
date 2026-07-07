defmodule Hive.MCP.Components.Tools.CreateForageItemTest do
  use Hive.MCPToolCase

  alias Hive.Forage.FeatureRequest
  alias Hive.MCP.Components.Tools.CreateForageItem

  test "creates a forage item for an authenticated caller" do
    user = mcp_user("create-forage@example.com", :collaborator)

    response =
      CreateForageItem.call(mcp_conn(user), %{
        "type" => "feedback",
        "title" => "Clearer onboarding",
        "description" => "The onboarding flow should explain the first task more clearly."
      })
      |> response_json()

    assert %{
             "destination" => "hive_item",
             "type" => "feedback",
             "title" => "Clearer onboarding",
             "hive_url" => hive_url,
             "external_url" => nil
           } = response["forage_item"]

    assert hive_url =~ "/forage/items/manual/"

    assert [%FeatureRequest{type: :feedback, title: "Clearer onboarding"}] =
             Repo.all(FeatureRequest)
  end

  test "returns invalid details for invalid attributes" do
    user = mcp_user("invalid-forage@example.com")

    response =
      CreateForageItem.call(mcp_conn(user), %{
        "title" => "",
        "description" => "short"
      })
      |> response_json()

    assert response["error"] == "invalid"
    assert response["details"]["title"] != []
    assert response["details"]["description"] != []
  end

  test "rejects anonymous callers" do
    response =
      CreateForageItem.call(mcp_conn(nil), %{
        "title" => "Anonymous idea",
        "description" => "This should not be accepted from an anonymous caller."
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
  end
end
