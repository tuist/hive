defmodule HiveWeb.WellKnownControllerTest do
  use HiveWeb.ConnCase, async: true

  describe "GET /.well-known/mcp/server-card.json" do
    test "returns the MCP server card", %{conn: conn} do
      conn = get(conn, ~p"/.well-known/mcp/server-card.json")

      response = json_response(conn, 200)

      assert response["serverInfo"] == %{"name" => "hive", "version" => "0.2.0"}
      assert response["transport"] == %{"endpoint" => "/mcp"}
      assert response["capabilities"] == ["tools", "prompts"]
    end
  end

  describe "GET /.well-known/oauth-authorization-server" do
    test "returns OAuth metadata", %{conn: conn} do
      conn = get(conn, ~p"/.well-known/oauth-authorization-server")

      response = json_response(conn, 200)

      assert response["issuer"] == "http://www.example.com"
      assert response["authorization_endpoint"] == "http://www.example.com/oauth2/authorize"
      assert response["token_endpoint"] == "http://www.example.com/oauth2/token"
      assert response["registration_endpoint"] == "http://www.example.com/oauth2/register"
      assert response["scopes_supported"] == ["mcp"]
      assert "S256" in response["code_challenge_methods_supported"]
    end
  end

  describe "GET /.well-known/oauth-protected-resource/mcp" do
    test "returns MCP protected resource metadata", %{conn: conn} do
      conn = get(conn, ~p"/.well-known/oauth-protected-resource/mcp")

      response = json_response(conn, 200)

      assert response["resource"] == "http://www.example.com/mcp"
      assert response["resource_name"] == "Hive MCP"
      assert response["authorization_servers"] == ["http://www.example.com"]
      assert response["bearer_methods_supported"] == ["header"]
      assert response["scopes_supported"] == ["mcp"]
    end
  end
end
