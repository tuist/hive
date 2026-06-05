defmodule HiveWeb.OAuth.TokenControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Boruta.Oauth.Error
  alias Boruta.Oauth.TokenResponse

  describe "POST /oauth2/token" do
    test "delegates token handling to Boruta", %{conn: conn} do
      expect(Boruta.Oauth, :token, fn conn, module ->
        assert module == HiveWeb.OAuth.TokenController
        Plug.Conn.send_resp(conn, 204, "")
      end)

      conn = post(conn, ~p"/oauth2/token", %{"grant_type" => "authorization_code"})

      assert response(conn, 204) == ""
    end
  end

  test "token_success/2 returns cache-safe token JSON" do
    conn =
      HiveWeb.OAuth.TokenController.token_success(build_conn(), %TokenResponse{
        token_type: "bearer",
        access_token: "access-token",
        expires_in: 3600,
        refresh_token: "refresh-token"
      })

    assert get_resp_header(conn, "pragma") == ["no-cache"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert json_response(conn, 200) == %{
             "token_type" => "bearer",
             "access_token" => "access-token",
             "expires_in" => 3600,
             "refresh_token" => "refresh-token"
           }
  end

  test "token_error/2 returns OAuth error JSON" do
    conn =
      HiveWeb.OAuth.TokenController.token_error(build_conn(), %Error{
        status: :unauthorized,
        error: :invalid_client,
        error_description: "Invalid client."
      })

    assert json_response(conn, 401) == %{
             "error" => "invalid_client",
             "error_description" => "Invalid client."
           }
  end
end
