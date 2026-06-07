defmodule Hive.MCP.Components.Tools.SpecsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.MCP.Components.Tools.AddSpecComment
  alias Hive.MCP.Components.Tools.CreateSpec
  alias Hive.MCP.Components.Tools.GetSpec
  alias Hive.MCP.Components.Tools.ListSpecs
  alias Hive.MCP.Components.Tools.UpdateSpec
  alias Hive.Specs

  defp user do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "test",
        provider_uid: "alice@example.com"
      })

    user
  end

  defp conn(user), do: %Plug.Conn{assigns: %{current_user: user}}

  defp response_json(response) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = response
    JSON.decode!(text)
  end

  test "creates, lists, fetches, updates, and comments on a spec" do
    user = user()

    created =
      CreateSpec.call(conn(user), %{
        "title" => "GitHub sign-in",
        "body" => "Add GitHub sign-in for requesters."
      })
      |> response_json()

    assert %{"spec" => %{"id" => id, "revision" => 1}} = created
    assert [%{"revision" => 1, "title" => "GitHub sign-in"}] = created["spec"]["revisions"]

    listed = ListSpecs.call(conn(user), %{}) |> response_json()
    assert [%{"id" => ^id}] = listed["specs"]

    fetched = GetSpec.call(conn(user), %{"id" => id}) |> response_json()
    assert fetched["spec"]["title"] == "GitHub sign-in"

    updated =
      UpdateSpec.call(conn(user), %{
        "id" => id,
        "expected_revision" => 1,
        "title" => "GitHub OAuth",
        "body" => "Updated proposal.",
        "status" => "proposed"
      })
      |> response_json()

    assert updated["spec"]["title"] == "GitHub OAuth"
    assert updated["spec"]["revision"] == 2
    assert Enum.map(updated["spec"]["revisions"], & &1["revision"]) == [2, 1]

    commented =
      AddSpecComment.call(conn(user), %{"spec_id" => id, "body" => "This looks ready."})
      |> response_json()

    assert [%{"body" => "This looks ready.", "author" => "alice@example.com"}] =
             commented["spec"]["comments"]
  end

  test "rejects stale local edits" do
    user = user()
    {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
    {:ok, _spec} = Specs.update_spec(spec, %{"title" => "Remote edit"}, user)

    response =
      UpdateSpec.call(conn(user), %{
        "id" => spec.id,
        "expected_revision" => 1,
        "title" => "Local edit"
      })
      |> response_json()

    assert response["error"] == "stale_revision"
    assert response["current_revision"] == 2
  end
end
