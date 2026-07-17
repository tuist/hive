defmodule HiveWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint HiveWeb.Endpoint

      use HiveWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Hive.DataCase
      import HiveWeb.ConnCase
    end
  end

  setup tags do
    Hive.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Persists a user for `email` and puts them in the connection's session.
  Returns `{conn, user}`.
  """
  def sign_in(conn, email) do
    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    {Plug.Test.init_test_session(conn, %{user_id: user.id}), user}
  end

  @doc "Persists a user, OAuth client, and access token for an authenticated controller test."
  def mobile_access_token!(email, scope, resource) do
    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    {:ok, client} =
      %Boruta.Ecto.Client{}
      |> Boruta.Ecto.Client.create_changeset(%{
        name: "Controller test client",
        redirect_uris: ["http://client.example/callback"],
        supported_grant_types: ["authorization_code", "refresh_token"],
        pkce: true,
        public_refresh_token: true,
        public_revoke: true
      })
      |> Hive.Repo.insert()

    {:ok, token} =
      %Boruta.Ecto.Token{}
      |> Boruta.Ecto.Token.changeset(%{
        client_id: client.id,
        sub: user.id,
        scope: scope,
        resource: resource,
        access_token_ttl: 60
      })
      |> Hive.Repo.insert()

    {token, user}
  end
end
