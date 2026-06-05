defmodule HiveWeb.MCPControllerTest do
  use HiveWeb.ConnCase, async: true

  describe "POST /mcp" do
    test "returns a bearer challenge when not authenticated", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/mcp", Jason.encode!(%{}))

      assert json_response(conn, 401) == %{
               "error" => "invalid_token",
               "error_description" => "Missing or invalid access token."
             }

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer realm="hive-mcp", resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp")
             ]
    end
  end
end
