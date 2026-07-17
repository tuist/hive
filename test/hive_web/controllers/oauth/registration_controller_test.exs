defmodule HiveWeb.OAuth.RegistrationControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Boruta.Ecto.Client
  alias Hive.Repo

  describe "POST /oauth2/register" do
    test "registers a public native client that requires PKCE", %{conn: conn} do
      conn =
        post(conn, ~p"/oauth2/register", %{
          "client_name" => "Hive Mobile",
          "redirect_uris" => ["dev.tuist.hive://oauth2redirect"],
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "token_endpoint_auth_method" => "none"
        })

      response = json_response(conn, 201)

      assert response["client_id"]
      refute response["client_secret"]
      refute response["client_secret_expires_at"]
      assert response["client_name"] == "Hive Mobile"
      assert response["redirect_uris"] == ["dev.tuist.hive://oauth2redirect"]
      assert response["grant_types"] == ["authorization_code", "refresh_token"]
      assert response["token_endpoint_auth_method"] == "none"

      assert %Client{
               confidential: false,
               pkce: true,
               public_refresh_token: true,
               public_revoke: true,
               supported_grant_types: ["authorization_code", "refresh_token", "revoke"]
             } = Repo.get!(Client, response["client_id"])
    end

    test "rejects jwks_uri to avoid server-side URL fetching", %{conn: conn} do
      conn =
        post(conn, ~p"/oauth2/register", %{
          "client_name" => "hive-mcp-client",
          "redirect_uris" => ["http://localhost:1234/callback"],
          "jwks_uri" => "http://169.254.169.254/latest/meta-data"
        })

      assert json_response(conn, 400) == %{
               "error" => "invalid_client_metadata",
               "error_description" => "jwks_uri is not supported. Provide inline jwks instead."
             }
    end

    test "ignores malformed metadata for public clients instead of crashing", %{conn: conn} do
      conn =
        post(conn, ~p"/oauth2/register", %{
          "client_name" => "hive-mcp-client",
          "redirect_uris" => ["http://localhost:1234/callback"],
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "token_endpoint_auth_method" => "none",
          "metadata" => "not-a-map"
        })

      assert %{"token_endpoint_auth_method" => "none"} = json_response(conn, 201)
    end
  end
end
