defmodule Hive.MCP.Components.Tools.Whoami do
  @moduledoc false

  use Hive.MCP.Tool,
    name: "whoami",
    title: "Current User",
    schema: %{
      "type" => "object",
      "properties" => %{}
    },
    output_schema:
      Hive.MCP.Tool.result_schema(
        %{
          "id" => %{"type" => "string"},
          "email" => %{"type" => "string"},
          "role" => %{"type" => "string"}
        },
        ["id", "email", "role"]
      )

  alias Hive.Auth

  @impl EMCP.Tool
  def description, do: "Return the authenticated Hive user for this MCP session."

  @impl EMCP.Tool
  def call(conn, _args) do
    user = conn.assigns.current_user

    json_response(%{
      id: user.id,
      email: user.email,
      role: Auth.role(user) |> Atom.to_string()
    })
  end
end
