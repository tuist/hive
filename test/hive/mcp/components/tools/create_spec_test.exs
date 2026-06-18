defmodule Hive.MCP.Components.Tools.CreateSpecTest do
  use Hive.MCPToolCase

  alias Hive.MCP.Components.Tools.CreateSpec

  test "creates specs with default status and visibility" do
    user = mcp_user()

    response =
      create_spec(user, "GitHub sign-in", %{
        "body" => "Add GitHub sign-in for requesters.",
        "summary" => "Let requesters authenticate with GitHub."
      })

    assert %{"spec" => %{"number" => number, "revision" => 1}} = response
    assert is_integer(number)
    assert response["spec"]["summary"] == "Let requesters authenticate with GitHub."
    assert response["spec"]["status"] == "draft"
    assert response["spec"]["visibility"] == "public"

    assert [%{"revision" => 1, "title" => "GitHub sign-in"}] =
             response["spec"]["revisions"]
  end

  test "does not skip numbers when a create rolls back after inserting the spec" do
    user = mcp_user("numbers@example.com")
    first = create_spec(user, "First spec")

    invalid_response =
      CreateSpec.call(mcp_conn(user), %{
        "title" => "Invalid meadow spec",
        "body" => "This create reaches meadow association before failing.",
        "meadow_ids" => [Ecto.UUID.generate()]
      })
      |> response_json()

    assert %{
             "error" => "invalid",
             "details" => %{"meadow_ids" => ["contains unknown meadows"]}
           } = invalid_response

    second = create_spec(user, "Second spec")

    assert second["spec"]["number"] == first["spec"]["number"] + 1
  end

  defp create_spec(user, title, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "title" => title,
          "body" => "This spec has enough body text."
        },
        attrs
      )

    user
    |> mcp_conn()
    |> CreateSpec.call(attrs)
    |> response_json()
  end
end
