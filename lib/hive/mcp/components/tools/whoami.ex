defmodule Hive.MCP.Components.Tools.Whoami do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "whoami",
    title: "Current User",
    schema: %{
      "type" => "object",
      "properties" => %{}
    }

  alias Hive.Auth
  alias Hive.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Return the authenticated Hive user for this MCP session."

  @impl EMCP.Tool
  def call(conn, _args) do
    user = conn.assigns.current_user

    Tool.json_response(%{
      id: user.id,
      email: user.email,
      role: Auth.role(user) |> Atom.to_string()
    })
  end
end
