defmodule Hive.MCP.Components.Tools.UpdateSpecTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.MCP.Components.Tools.UpdateSpec
  alias Hive.Specs

  test "updates specs referenced by shared path" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    response =
      UpdateSpec.call(mcp_conn(user), %{
        "id" => "/specs/#{spec.number}",
        "expected_revision" => 1,
        "title" => "GitHub OAuth",
        "body" => "Updated proposal.",
        "summary" => "Use OAuth to authenticate requesters through GitHub.",
        "status" => "proposed"
      })
      |> response_json()

    assert response["spec"]["title"] == "GitHub OAuth"
    assert response["spec"]["summary"] == "Use OAuth to authenticate requesters through GitHub."
    assert response["spec"]["revision"] == 2
    assert Enum.map(response["spec"]["revisions"], & &1["revision"]) == [2, 1]
  end

  test "rejects stale local edits" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
    {:ok, _spec} = Specs.update_spec(spec, %{"title" => "Remote edit"}, user)

    response =
      UpdateSpec.call(mcp_conn(user), %{
        "id" => spec.id,
        "expected_revision" => 1,
        "title" => "Local edit"
      })
      |> response_json()

    assert response["error"] == "stale_revision"
    assert response["current_revision"] == 2
  end

  test "reports a locked spec instead of failing the update" do
    user = mcp_user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

    stub(Specs, :update_spec, fn _spec, _attrs, _user -> {:error, :locked} end)

    response =
      UpdateSpec.call(mcp_conn(user), %{
        "id" => spec.id,
        "expected_revision" => 1,
        "summary" => "A small tweak."
      })
      |> response_json()

    assert response["error"] == "locked"
  end
end
