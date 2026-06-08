defmodule Hive.MCPToolCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      use Hive.DataCase, async: true

      import Hive.MCPToolCase
    end
  end

  def mcp_user(email \\ "alice@example.com") do
    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{
        email: email,
        provider: "test",
        provider_uid: email
      })

    user
  end

  def mcp_conn(user), do: %Plug.Conn{assigns: %{current_user: user}}

  def response_json(response) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = response
    JSON.decode!(text)
  end
end
