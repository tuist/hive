defmodule HiveWeb.Api.V1.DevSessionController do
  @moduledoc """
  Dev-only endpoint that mints a mobile session for `test@hive.dev`.

  Mounted only when `:hive, :dev_routes` is `true` (see `config/dev.exs`).
  The mobile applications call it to skip the OAuth browser flow while
  iterating locally.
  """

  use HiveWeb, :controller

  alias Hive.Accounts
  alias Hive.OAuth.Scopes
  alias HiveWeb.RequestOrigin

  @client_name "Hive dev mobile client"
  @redirect_uri "dev.tuist.hive://oauth2redirect"

  def create(conn, _params) do
    if Application.get_env(:hive, :dev_routes, false) do
      user = ensure_test_user()
      {:ok, client} = ensure_client()

      origin = RequestOrigin.from_conn(conn)
      resource = origin <> "/api/v1"
      scope = Scopes.mobile_scopes() |> Enum.join(" ")

      {:ok, token} = create_token(client, user, scope, resource)

      now = DateTime.utc_now() |> DateTime.to_unix()

      json(conn, %{
        server: origin,
        token_endpoint: origin <> "/oauth2/token",
        revocation_endpoint: origin <> "/oauth2/revoke",
        client_id: client.id,
        resource: resource,
        access_token: token.value,
        refresh_token: token.refresh_token,
        expires_at: now + token.access_token_ttl
      })
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(:not_found, ~s({"error":"not_found","error_description":"Not found."}))
    end
  end

  defp ensure_test_user do
    user =
      case Accounts.get_user_by_email("test@hive.dev") do
        nil ->
          {:ok, user} =
            Accounts.upsert_from_auth(%{
              email: "test@hive.dev",
              provider: "dev",
              provider_uid: "test@hive.dev"
            })

          user

        user ->
          user
      end

    {:ok, user} = Accounts.update_user_role(user, :admin)
    user
  end

  defp ensure_client do
    case Hive.Repo.get_by(Boruta.Ecto.Client, name: @client_name) do
      %Boruta.Ecto.Client{} = client ->
        {:ok, client}

      nil ->
        %Boruta.Ecto.Client{}
        |> Boruta.Ecto.Client.create_changeset(%{
          name: @client_name,
          redirect_uris: [@redirect_uri],
          supported_grant_types: ["authorization_code", "refresh_token", "revoke"],
          pkce: true,
          confidential: false,
          public_refresh_token: true,
          public_revoke: true
        })
        |> Hive.Repo.insert()
    end
  end

  defp create_token(client, user, scope, resource) do
    %Boruta.Ecto.Token{}
    |> Boruta.Ecto.Token.changeset_with_refresh_token(%{
      client_id: client.id,
      sub: user.id,
      scope: scope,
      resource: resource,
      access_token_ttl: client.access_token_ttl
    })
    |> Hive.Repo.insert()
  end
end
