defmodule HiveWeb.OAuth.RegistrationControllerTest do
  use HiveWeb.ConnCase, async: true

  describe "POST /oauth2/register" do
    test "registers a public MCP OAuth client", %{conn: conn} do
      conn =
        post(conn, ~p"/oauth2/register", %{
          "client_name" => "hive-mcp-client",
          "redirect_uris" => ["http://localhost:1234/callback"],
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "token_endpoint_auth_method" => "none"
        })

      response = json_response(conn, 201)

      assert response["client_id"]
      assert response["client_secret"]
      assert response["client_secret_expires_at"] == 0
      assert response["client_name"] == "hive-mcp-client"
      assert response["redirect_uris"] == ["http://localhost:1234/callback"]
      assert response["grant_types"] == ["authorization_code", "refresh_token"]
      assert response["token_endpoint_auth_method"] == "none"
    end
  end
end
