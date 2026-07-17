defmodule HiveWeb.OAuth.NativeLoginTest do
  use HiveWeb.ConnCase, async: true

  @redirect_uri "dev.tuist.hive://oauth2redirect"
  @resource "http://www.example.com/api/v1"

  test "a dynamically registered native client exchanges a PKCE code", %{conn: conn} do
    registration_conn =
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Hive Mobile",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    client_id = json_response(registration_conn, 201)["client_id"]
    verifier = String.duplicate("native-code-verifier-", 3)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    {signed_in_conn, user} = sign_in(recycle(conn), "mobile@example.com")

    authorize_conn =
      post(
        signed_in_conn,
        ~p"/oauth2/authorize?response_type=code&client_id=#{client_id}&redirect_uri=#{@redirect_uri}&scope=mobile&resource=#{@resource}&state=native-state&code_challenge=#{challenge}&code_challenge_method=S256",
        %{"decision" => "approve"}
      )

    code = authorization_code(authorize_conn)

    token_conn =
      post(recycle(conn), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "code" => code,
        "client_id" => client_id,
        "redirect_uri" => @redirect_uri,
        "resource" => @resource,
        "code_verifier" => verifier
      })

    assert %{
             "access_token" => access_token,
             "refresh_token" => refresh_token,
             "token_type" => "bearer"
           } = json_response(token_conn, 200)

    assert is_binary(access_token)
    assert is_binary(refresh_token)

    me_conn =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> get(~p"/api/v1/me")

    assert json_response(me_conn, 200)["data"]["id"] == user.id

    refresh_conn =
      post(recycle(conn), ~p"/oauth2/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token,
        "client_id" => client_id,
        "resource" => @resource
      })

    assert %{
             "access_token" => refreshed_access_token,
             "refresh_token" => refreshed_refresh_token
           } = json_response(refresh_conn, 200)

    refreshed_me_conn =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{refreshed_access_token}")
      |> get(~p"/api/v1/me")

    assert json_response(refreshed_me_conn, 200)["data"]["email"] == "mobile@example.com"

    revoke_conn =
      post(recycle(conn), ~p"/oauth2/revoke", %{
        "token" => refreshed_refresh_token,
        "token_type_hint" => "refresh_token",
        "client_id" => client_id
      })

    assert response(revoke_conn, 200) == ""

    rejected_refresh_conn =
      post(recycle(conn), ~p"/oauth2/token", %{
        "grant_type" => "refresh_token",
        "refresh_token" => refreshed_refresh_token,
        "client_id" => client_id,
        "resource" => @resource
      })

    assert json_response(rejected_refresh_conn, 400)["error"] == "invalid_grant"
  end

  test "a dynamically registered native client rejects the wrong verifier", %{conn: conn} do
    registration_conn =
      post(conn, ~p"/oauth2/register", %{
        "client_name" => "Hive Mobile",
        "redirect_uris" => [@redirect_uri],
        "grant_types" => ["authorization_code"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    client_id = json_response(registration_conn, 201)["client_id"]
    verifier = String.duplicate("native-code-verifier-", 3)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    {signed_in_conn, _user} = sign_in(recycle(conn), "mobile-verifier@example.com")

    authorize_conn =
      post(
        signed_in_conn,
        ~p"/oauth2/authorize?response_type=code&client_id=#{client_id}&redirect_uri=#{@redirect_uri}&scope=mobile&resource=#{@resource}&state=native-state&code_challenge=#{challenge}&code_challenge_method=S256",
        %{"decision" => "approve"}
      )

    code = authorization_code(authorize_conn)

    token_conn =
      post(recycle(conn), ~p"/oauth2/token", %{
        "grant_type" => "authorization_code",
        "code" => code,
        "client_id" => client_id,
        "redirect_uri" => @redirect_uri,
        "resource" => @resource,
        "code_verifier" => String.duplicate("wrong-code-verifier-", 3)
      })

    assert json_response(token_conn, 400) == %{
             "error" => "invalid_request",
             "error_description" => "Code verifier is invalid."
           }
  end

  defp authorization_code(conn) do
    uri = conn |> redirected_to() |> URI.parse()
    URI.decode_query(uri.query)["code"]
  end
end
