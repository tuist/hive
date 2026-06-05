defmodule HiveWeb.OAuth.AuthorizeControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error
  alias Boruta.Oauth.ResourceOwner
  alias Hive.Accounts
  alias Hive.Auth

  describe "GET /oauth2/authorize" do
    test "redirects anonymous users to login and stores the return path", %{conn: conn} do
      stub(Auth, :current_user, fn _conn -> nil end)

      conn = get(conn, ~p"/oauth2/authorize?client_id=client&scope=mcp")

      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, :user_return_to) == "/oauth2/authorize?client_id=client&scope=mcp"
    end

    test "authorizes signed-in users through Boruta", %{conn: conn} do
      {:ok, user} =
        Accounts.upsert_from_auth(%{
          email: "alice@example.com",
          provider: "test",
          provider_uid: "alice@example.com"
        })

      stub(Auth, :current_user, fn _conn -> user end)

      expect(Boruta.Oauth, :authorize, fn conn, %ResourceOwner{} = resource_owner, module ->
        assert resource_owner.sub == user.id
        assert resource_owner.username == user.email
        assert module == HiveWeb.OAuth.AuthorizeController

        Plug.Conn.send_resp(conn, 204, "")
      end)

      conn = get(conn, ~p"/oauth2/authorize?client_id=client&scope=mcp")

      assert response(conn, 204) == ""
    end
  end

  test "authorize_success/2 redirects to Boruta's redirect URL" do
    conn = build_conn()

    response = %AuthorizeResponse{
      type: :code,
      redirect_uri: "http://client.example/callback",
      code: %Boruta.Oauth.Token{type: "code", value: "code"},
      state: "state"
    }

    conn = HiveWeb.OAuth.AuthorizeController.authorize_success(conn, response)

    assert redirected_to(conn) == "http://client.example/callback?code=code&state=state"
  end

  test "authorize_error/2 returns JSON errors without a redirect format" do
    conn = build_conn()

    conn =
      HiveWeb.OAuth.AuthorizeController.authorize_error(conn, %Error{
        status: :bad_request,
        error: :invalid_request,
        error_description: "Invalid request."
      })

    assert json_response(conn, 400) == %{
             "error" => "invalid_request",
             "error_description" => "Invalid request."
           }
  end

  test "authorize_error/2 redirects formatted OAuth errors" do
    conn = build_conn()

    conn =
      HiveWeb.OAuth.AuthorizeController.authorize_error(conn, %Error{
        status: :bad_request,
        error: :invalid_request,
        error_description: "Invalid request.",
        format: :query,
        redirect_uri: "http://client.example/callback",
        state: "state"
      })

    uri = redirected_to(conn) |> URI.parse()

    assert %{scheme: "http", host: "client.example", path: "/callback"} = uri

    assert URI.decode_query(uri.query) == %{
             "error" => "invalid_request",
             "error_description" => "Invalid request.",
             "state" => "state"
           }
  end
end
