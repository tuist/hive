defmodule Hive.MCP.Components.Tools.UpdateSpecTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.MCP.Components.Tools.UpdateSpec
  alias Hive.Projects
  alias Hive.Specs

  test "updates specs referenced by shared path" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive"), visibility: "public"})

    {:ok, private_project} =
      Projects.create_project(%{name: unique_name("Atlas"), visibility: "private"})

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "Draft", "body" => "Initial proposal.", "project_id" => project.id},
        user
      )

    response =
      UpdateSpec.call(mcp_conn(user), %{
        "id" => "/specs/#{spec.number}",
        "expected_revision" => 1,
        "title" => "GitHub OAuth",
        "body" => "Updated proposal.",
        "summary" => "Use OAuth to authenticate requesters through GitHub.",
        "status" => "proposed",
        "project_id" => private_project.id
      })
      |> response_json()

    assert response["spec"]["title"] == "GitHub OAuth"
    assert response["spec"]["summary"] == "Use OAuth to authenticate requesters through GitHub."
    assert response["spec"]["revision"] == 2
    assert response["spec"]["project"]["id"] == private_project.id
    assert response["spec"]["visibility"] == "private"
    assert Enum.map(response["spec"]["revisions"], & &1["revision"]) == [2, 1]
  end

  test "rejects stale local edits" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "Draft", "body" => "Initial proposal.", "project_id" => project.id},
        user
      )

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

  test "reports a locked error instead of crashing when a write is contended" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, spec} =
      Specs.create_spec(
        %{"title" => "Draft", "body" => "Initial proposal.", "project_id" => project.id},
        user
      )

    expect(Specs, :update_spec, fn _spec, _attrs, _user -> {:error, :locked} end)

    response =
      UpdateSpec.call(mcp_conn(user), %{
        "id" => spec.id,
        "expected_revision" => 1,
        "title" => "Contended edit"
      })
      |> response_json()

    assert response["error"] == "locked"
    assert is_binary(response["message"])
  end
end
