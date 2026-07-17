defmodule HiveWeb.WellKnownController do
  use HiveWeb, :controller

  alias HiveWeb.RequestOrigin

  @mcp_path "/mcp"
  @oauth_authorize_path "/oauth2/authorize"
  @oauth_token_path "/oauth2/token"
  @oauth_revoke_path "/oauth2/revoke"
  @oauth_registration_path "/oauth2/register"

  def mcp_server_card(conn, _params) do
    server = Hive.MCP.Server.server()

    capabilities =
      [
        {map_size(server.tools) > 0, "tools"},
        {map_size(server.resources) > 0, "resources"},
        {map_size(server.prompts) > 0, "prompts"}
      ]
      |> Enum.filter(fn {present, _name} -> present end)
      |> Enum.map(fn {_present, name} -> name end)

    json(conn, %{
      serverInfo: %{name: server.name, version: server.version},
      transport: %{endpoint: @mcp_path},
      capabilities: capabilities
    })
  end

  def oauth_authorization_server(conn, _params) do
    issuer = RequestOrigin.from_conn(conn)

    json(conn, %{
      issuer: issuer,
      authorization_endpoint: "#{issuer}#{@oauth_authorize_path}",
      token_endpoint: "#{issuer}#{@oauth_token_path}",
      revocation_endpoint: "#{issuer}#{@oauth_revoke_path}",
      registration_endpoint: "#{issuer}#{@oauth_registration_path}",
      grant_types_supported: ["authorization_code", "refresh_token"],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      resource_parameter_supported: true,
      scopes_supported: ["api", "mcp", "mobile"],
      token_endpoint_auth_methods_supported: [
        "none",
        "client_secret_basic",
        "client_secret_post",
        "client_secret_jwt",
        "private_key_jwt"
      ]
    })
  end

  def oauth_protected_resource(conn, params) do
    origin = RequestOrigin.from_conn(conn)

    case Map.get(params, "resource_path", []) do
      [] ->
        json(conn, protected_resource_metadata(origin, "", "Hive", ["api", "mcp", "mobile"]))

      ["api"] ->
        json(
          conn,
          protected_resource_metadata(
            origin,
            "/api",
            "Hive application programming interface",
            ["api"]
          )
        )

      ["mcp"] ->
        json(conn, protected_resource_metadata(origin, @mcp_path, "Hive MCP", ["mcp"]))

      ["api", "v1"] ->
        json(conn, protected_resource_metadata(origin, "/api/v1", "Hive Mobile", ["mobile"]))

      _ ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp protected_resource_metadata(origin, path, name, scopes) do
    %{
      resource: "#{origin}#{path}",
      resource_name: name,
      authorization_servers: [origin],
      bearer_methods_supported: ["header"],
      scopes_supported: scopes
    }
  end
end
