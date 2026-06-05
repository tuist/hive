defmodule HiveWeb.MCPControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Token
  alias Hive.Accounts
  alias Hive.Repo

  @initialize %{
    "jsonrpc" => "2.0",
    "id" => 1,
    "method" => "initialize",
    "params" => %{
      "protocolVersion" => "2025-03-26",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "test", "version" => "0.1.0"}
    }
  }

  describe "POST /mcp" do
    test "returns a bearer challenge when not authenticated", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", JSON.encode!(%{}))

      assert json_response(conn, 401) == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer realm="hive-mcp", resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp")
             ]
    end

    test "accepts a valid Boruta access token with the mcp scope", %{conn: conn} do
      token = oauth_access_token!("alice@example.com", "mcp", "http://www.example.com/mcp")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.value}")
        |> post_mcp(@initialize)

      response = json_response(conn, 200)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["serverInfo"]["name"] == "hive"
      assert get_resp_header(conn, "mcp-session-id") != []
    end

    test "rejects a valid Boruta access token without the mcp scope", %{conn: conn} do
      token = oauth_access_token!("alice@example.com", "profile", "http://www.example.com/mcp")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.value}")
        |> post_mcp(@initialize)

      assert json_response(conn, 401) == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end

    test "rejects a valid Boruta access token for another resource", %{conn: conn} do
      token = oauth_access_token!("alice@example.com", "mcp", "http://www.example.com/other")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.value}")
        |> post_mcp(@initialize)

      assert json_response(conn, 401) == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }
    end
  end

  defp post_mcp(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/mcp", JSON.encode!(body))
  end

  defp oauth_access_token!(email, scope, resource) do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: email,
        provider: "test",
        provider_uid: email
      })

    {:ok, client} =
      %Client{}
      |> Client.create_changeset(%{
        name: "MCP test client",
        redirect_uris: ["http://client.example/callback"],
        supported_grant_types: ["authorization_code", "refresh_token"],
        pkce: true,
        public_refresh_token: true,
        public_revoke: true
      })
      |> Repo.insert()

    {:ok, token} =
      %Token{}
      |> Token.changeset(%{
        client_id: client.id,
        sub: user.id,
        scope: scope,
        resource: resource,
        access_token_ttl: 60
      })
      |> Repo.insert()

    token
  end
end
