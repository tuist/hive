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

    test "returns request responses inline when the session has a stale event stream registration",
         %{conn: conn} do
      token =
        oauth_access_token!("stale-session@example.com", "mcp", "http://www.example.com/mcp")

      init_conn =
        conn
        |> authenticated_mcp_conn(token)
        |> post_mcp(@initialize)

      [session_id] = get_resp_header(init_conn, "mcp-session-id")

      stale_pid = spawn(fn -> :ok end)
      ref = Process.monitor(stale_pid)
      assert_receive {:DOWN, ^ref, :process, ^stale_pid, _reason}
      EMCP.SessionStore.ETS.register(session_id, stale_pid)

      conn =
        build_conn()
        |> authenticated_mcp_conn(token)
        |> put_req_header("mcp-session-id", session_id)
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/list",
          "params" => %{}
        })

      response = json_response(conn, 200)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2
      assert is_list(response["result"]["tools"])
    end

    test "advertises an output schema for every tool", %{conn: conn} do
      token = oauth_access_token!("schemas@example.com", "mcp", "http://www.example.com/mcp")

      conn =
        build_conn()
        |> authenticated_mcp_conn(token)
        |> put_req_header("mcp-session-id", initialized_session_id(conn, token))
        |> post_mcp(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}})

      tools = json_response(conn, 200)["result"]["tools"]

      assert tools != []

      for tool <- tools do
        assert tool["outputSchema"]["type"] == "object",
               "tool #{tool["name"]} is missing an output schema"
      end
    end

    test "returns structured content alongside the text content", %{conn: conn} do
      token = oauth_access_token!("structured@example.com", "mcp", "http://www.example.com/mcp")

      conn =
        build_conn()
        |> authenticated_mcp_conn(token)
        |> put_req_header("mcp-session-id", initialized_session_id(conn, token))
        |> post_mcp(%{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/call",
          "params" => %{"name" => "whoami", "arguments" => %{}}
        })

      result = json_response(conn, 200)["result"]

      assert [%{"type" => "text", "text" => text}] = result["content"]
      assert result["structuredContent"]["email"] == "structured@example.com"
      assert JSON.decode!(text) == result["structuredContent"]
    end

    test "negotiates the protocol version the client asked for", %{conn: conn} do
      token = oauth_access_token!("negotiate@example.com", "mcp", "http://www.example.com/mcp")

      conn =
        conn
        |> authenticated_mcp_conn(token)
        |> post_mcp(@initialize)

      assert json_response(conn, 200)["result"]["protocolVersion"] == "2025-03-26"
    end

    test "rejects an unsupported protocol version header", %{conn: conn} do
      token = oauth_access_token!("unsupported@example.com", "mcp", "http://www.example.com/mcp")

      conn =
        conn
        |> authenticated_mcp_conn(token)
        |> put_req_header("mcp-protocol-version", "1999-01-01")
        |> post_mcp(@initialize)

      assert json_response(conn, 400)["error"] == "Unsupported MCP protocol version: 1999-01-01"
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

  defp initialized_session_id(conn, token) do
    [session_id] =
      conn
      |> authenticated_mcp_conn(token)
      |> post_mcp(@initialize)
      |> get_resp_header("mcp-session-id")

    session_id
  end

  defp post_mcp(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/mcp", JSON.encode!(body))
  end

  defp authenticated_mcp_conn(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer #{token.value}")
    |> put_req_header("accept", "application/json, text/event-stream")
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
