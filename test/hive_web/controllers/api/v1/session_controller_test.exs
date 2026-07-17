defmodule HiveWeb.Api.V1.SessionControllerTest do
  use HiveWeb.ConnCase, async: true

  @resource "http://www.example.com/api/v1"

  test "returns a bearer challenge without an access token", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/me")

    assert json_response(conn, 401) == %{
             "error" => "invalid_token",
             "error_description" => "Missing or invalid access token."
           }

    assert get_resp_header(conn, "www-authenticate") == [
             ~s(Bearer realm="hive-mobile", resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/api/v1")
           ]
  end

  test "returns the user for a valid mobile token", %{conn: conn} do
    {token, user} = mobile_access_token!("mobile@example.com", "mobile", @resource)

    conn = conn |> authorize(token) |> get(~p"/api/v1/me")

    assert json_response(conn, 200) == %{
             "data" => %{
               "id" => user.id,
               "email" => "mobile@example.com",
               "name" => nil,
               "role" => to_string(user.role)
             }
           }
  end

  test "rejects another scope or protected resource", %{conn: conn} do
    {wrong_scope, _user} = mobile_access_token!("scope@example.com", "mcp", @resource)

    assert conn
           |> authorize(wrong_scope)
           |> get(~p"/api/v1/me")
           |> json_response(401)

    {wrong_resource, _user} =
      mobile_access_token!("resource@example.com", "mobile", "http://www.example.com/mcp")

    assert build_conn()
           |> authorize(wrong_resource)
           |> get(~p"/api/v1/me")
           |> json_response(401)
  end

  defp authorize(conn, token),
    do: put_req_header(conn, "authorization", "Bearer #{token.value}")
end
