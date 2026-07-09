defmodule Hive.MCP.Components.Tools.CreateSpecTest do
  use Hive.MCPToolCase
  use Mimic

  alias Hive.MCP.Components.Tools.CreateSpec
  alias Hive.Projects
  alias Hive.Specs

  test "creates specs with inherited project visibility" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive"), visibility: "public"})

    response =
      create_spec(user, "GitHub sign-in", %{
        "body" => "Add GitHub sign-in for requesters.",
        "summary" => "Let requesters authenticate with GitHub.",
        "project_id" => project.id
      })

    assert %{"spec" => %{"number" => number, "revision" => 1}} = response
    assert is_integer(number)
    assert response["spec"]["summary"] == "Let requesters authenticate with GitHub."
    assert response["spec"]["status"] == "draft"
    assert response["spec"]["visibility"] == "public"
    assert response["spec"]["visibility_override"] == nil
    assert response["spec"]["project"]["id"] == project.id

    assert [%{"revision" => 1, "title" => "GitHub sign-in"}] =
             response["spec"]["revisions"]
  end

  test "creates specs with a private override" do
    user = mcp_user()
    {:ok, project} = Projects.create_project(%{name: unique_name("Hive"), visibility: "public"})

    response =
      create_spec(user, "Private spec", %{
        "project_id" => project.id,
        "visibility_override" => "private"
      })

    assert response["spec"]["visibility"] == "private"
    assert response["spec"]["visibility_override"] == "private"
    assert response["spec"]["project"]["id"] == project.id
  end

  test "does not skip numbers when a create rolls back after inserting the spec" do
    user = mcp_user("numbers@example.com")
    first = create_spec(user, "First spec")

    invalid_response =
      CreateSpec.call(mcp_conn(user), %{
        "title" => "Invalid domain spec",
        "body" => "This create reaches domain association before failing.",
        "project_id" => first["spec"]["project"]["id"],
        "domain_ids" => [Ecto.UUID.generate()]
      })
      |> response_json()

    assert %{
             "error" => "invalid",
             "details" => %{"domain_ids" => ["contains unknown domains"]}
           } = invalid_response

    second = create_spec(user, "Second spec")

    assert second["spec"]["number"] == first["spec"]["number"] + 1
  end

  test "reports a locked error instead of crashing when a write is contended" do
    user = mcp_user()
    expect(Specs, :create_spec, fn _attrs, _user -> {:error, :locked} end)

    response =
      CreateSpec.call(mcp_conn(user), %{
        "title" => "Contended spec",
        "body" => "This create collides with an in-flight spec write."
      })
      |> response_json()

    assert response["error"] == "locked"
    assert is_binary(response["message"])
  end

  defp create_spec(user, title, attrs \\ %{}) do
    {:ok, project} = Projects.create_project(%{name: unique_name("Spec project")})

    attrs =
      Map.merge(
        %{
          "title" => title,
          "body" => "This spec has enough body text.",
          "project_id" => project.id
        },
        attrs
      )

    user
    |> mcp_conn()
    |> CreateSpec.call(attrs)
    |> response_json()
  end
end
