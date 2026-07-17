defmodule HiveWeb.OAuth.AuthorizeControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Token
  alias Hive.Repo

  describe "GET /oauth2/authorize" do
    test "redirects anonymous users to login and stores the return path", %{conn: conn} do
      conn = get(conn, ~p"/oauth2/authorize?client_id=client&scope=mcp")

      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, :user_return_to) == "/oauth2/authorize?client_id=client&scope=mcp"
    end

    test "renders a consent page for a signed-in user and valid client", %{conn: conn} do
      {conn, user} = sign_in(conn, "alice@example.com")
      client = oauth_client!()

      conn =
        get(
          conn,
          ~p"/oauth2/authorize?response_type=code&client_id=#{client.id}&redirect_uri=http://client.example/callback&scope=mcp&resource=http://www.example.com/mcp&state=state"
        )

      response = html_response(conn, 200)

      assert response =~ "Authorize MCP test client"
      assert response =~ "alice@example.com"
      assert response =~ "http://client.example/callback"
      assert response =~ "Model Context Protocol access"
      assert response =~ ~s(id="oauth-consent")
      assert response =~ ~s(name="viewport")
      assert response =~ ~s(/assets/js/app.css)
      assert response =~ ~s(data-part="client-info")
      assert response =~ ~s(data-part="form")
      assert response =~ ~s(data-part="approve-button")
      assert response =~ ~s(data-part="deny-button")
      refute Repo.exists?(Token)
      assert user.email == "alice@example.com"
    end

    test "issues an authorization code after consent approval", %{conn: conn} do
      {conn, user} = sign_in(conn, "alice@example.com")
      client = oauth_client!()

      conn =
        post(
          conn,
          ~p"/oauth2/authorize?response_type=code&client_id=#{client.id}&redirect_uri=http://client.example/callback&scope=mcp&resource=http://www.example.com/mcp&state=state",
          %{"decision" => "approve"}
        )

      uri = redirected_to(conn) |> URI.parse()
      query = URI.decode_query(uri.query)

      assert %{scheme: "http", host: "client.example", path: "/callback"} = uri
      assert query["state"] == "state"

      assert %Token{
               type: "code",
               sub: sub,
               scope: "mcp",
               resource: "http://www.example.com/mcp",
               redirect_uri: "http://client.example/callback",
               client_id: client_id
             } = Repo.get_by(Token, value: query["code"])

      assert sub == user.id
      assert client_id == client.id
    end

    test "does not issue an authorization code when consent is denied", %{conn: conn} do
      {conn, _user} = sign_in(conn, "alice@example.com")
      client = oauth_client!()

      conn =
        post(
          conn,
          ~p"/oauth2/authorize?response_type=code&client_id=#{client.id}&redirect_uri=http://client.example/callback&scope=mcp&resource=http://www.example.com/mcp&state=state",
          %{"decision" => "deny"}
        )

      assert html_response(conn, 403) =~ "Access was not granted"
      refute Repo.exists?(Token)
    end

    test "returns an OAuth JSON error for a signed-in invalid request", %{conn: conn} do
      {conn, _user} = sign_in(conn, "alice@example.com")

      conn = get(conn, ~p"/oauth2/authorize?client_id=not-a-client")

      assert json_response(conn, 400) == %{
               "error" => "invalid_request",
               "error_description" =>
                 "Request is not a valid OAuth request. Need a response_type param."
             }
    end
  end

  defp oauth_client! do
    {:ok, client} =
      %Client{}
      |> Client.create_changeset(%{
        name: "MCP test client",
        redirect_uris: ["http://client.example/callback"],
        supported_grant_types: ["authorization_code", "refresh_token"]
      })
      |> Repo.insert()

    client
  end
end
