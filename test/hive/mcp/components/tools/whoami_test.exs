defmodule Hive.MCP.Components.Tools.WhoamiTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.MCP.Components.Tools.Whoami

  test "returns the authenticated user's identity and Hive role" do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "test",
        provider_uid: "alice@example.com"
      })

    response = Whoami.call(%Plug.Conn{assigns: %{current_user: user}}, %{})

    assert %{
             "content" => [
               %{"type" => "text", "text" => text}
             ]
           } = response

    assert Jason.decode!(text) == %{
             "id" => user.id,
             "email" => "alice@example.com",
             "role" => "member"
           }
  end
end
