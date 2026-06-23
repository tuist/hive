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

  def mcp_user(email, role) do
    email
    |> mcp_user()
    |> set_mcp_role(role)
  end

  def set_mcp_role(user, role) do
    {:ok, user} = Hive.Accounts.update_user_role(user, role)
    user
  end

  def unique_name(prefix), do: "#{prefix} #{System.unique_integer([:positive])}"

  def mcp_conn(user), do: %Plug.Conn{assigns: %{current_user: user}}

  def response_json(response) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = response
    JSON.decode!(text)
  end
end
