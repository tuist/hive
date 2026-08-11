defmodule Hive.MCP.Components.Tools.DeleteSpecTest do
  use Hive.MCPToolCase

  alias Hive.Audit.Activity
  alias Hive.MCP.Components.Tools.DeleteSpec
  alias Hive.Projects
  alias Hive.Repo
  alias Hive.Specs
  alias Hive.Specs.Comment
  alias Hive.Specs.Revision
  alias Hive.Specs.Spec

  test "deletes a current spec and its dependent records for members" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Registry alerts",
          "body" => "Add registry latency alerts.",
          "project_id" => project.id
        },
        user
      )

    {:ok, comment} = Specs.add_comment(spec, %{"body" => "This is ready."}, user)

    response =
      DeleteSpec.call(mcp_conn(user), %{
        "id" => "/specs/#{spec.number}",
        "expected_revision" => spec.lock_version
      })
      |> response_json()

    assert response["deleted_spec"]["id"] == spec.id
    refute Repo.get(Spec, spec.id)
    refute Repo.get(Comment, comment.id)
    refute Repo.get_by(Revision, spec_id: spec.id)
    assert Repo.get_by!(Activity, action: "spec.deleted", target_id: spec.id)
  end

  test "refuses to delete a stale revision" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Registry alerts",
          "body" => "Add registry latency alerts.",
          "project_id" => project.id
        },
        user
      )

    {:ok, updated_spec} = Specs.update_spec(spec, %{"title" => "Registry alerting"}, user)

    response =
      DeleteSpec.call(mcp_conn(user), %{
        "id" => spec.id,
        "expected_revision" => spec.lock_version
      })
      |> response_json()

    assert response["error"] == "stale_revision"
    assert response["current_revision"] == updated_spec.lock_version
    assert Repo.get(Spec, spec.id)
  end

  test "rejects collaborators" do
    member = mcp_user("spec-delete-member@example.com", :member)
    collaborator = mcp_user("spec-delete-collaborator@example.com", :collaborator)
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive")})

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Registry alerts",
          "body" => "Add registry latency alerts.",
          "project_id" => project.id
        },
        member
      )

    response =
      DeleteSpec.call(mcp_conn(collaborator), %{
        "id" => spec.id,
        "expected_revision" => spec.lock_version
      })
      |> response_json()

    assert response == %{"error" => "unauthorized"}
    assert Repo.get(Spec, spec.id)
  end
end
