defmodule HiveWeb.Plugs.MCPAuthentication do
  @moduledoc false

  alias HiveWeb.Plugs.OAuthBearerAuthentication

  def init(opts), do: opts

  def call(conn, _opts) do
    OAuthBearerAuthentication.call(conn,
      scope: "mcp",
      resource_path: "/mcp",
      metadata_path: "/.well-known/oauth-protected-resource/mcp",
      realm: "hive-mcp",
      interface: "mcp"
    )
  end
end
