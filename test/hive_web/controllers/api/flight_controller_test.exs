defmodule HiveWeb.API.FlightControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Boruta.Ecto.Client
  alias Boruta.Ecto.Token
  alias Hive.Accounts
  alias Hive.Flights.Flight
  alias Hive.Projects
  alias Hive.Repo

  test "requires an application programming interface access token", %{conn: conn} do
    conn = get(conn, ~p"/api/flights")

    assert json_response(conn, 401) == %{
             "error" => "invalid_token",
             "error_description" => "Missing or invalid access token."
           }

    assert get_resp_header(conn, "www-authenticate") == [
             ~s(Bearer realm="hive-api", resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/api")
           ]
  end

  test "lists Flights without sessions and returns a complete Flight by identifier", %{conn: conn} do
    {user, token} = oauth_access_token!("flight-api@example.com", :member)
    repository = repository()

    flight =
      %Flight{}
      |> Flight.changeset(%{
        forage_item_id: "grafana_alert:#{Ecto.UUID.generate()}",
        status: :succeeded,
        objective: :reproduce,
        objective_outcome: :not_reproduced,
        runner: "microsandbox",
        repository_full_name: "tuist/#{repository.name}",
        repository_id: repository.id,
        requested_by_id: user.id,
        input: %{"title" => "High latency"},
        session: %{
          "source" => %{"base_revision" => "abc123"},
          "messages" => [%{"role" => "assistant", "content" => "Handled it."}]
        },
        result: %{"summary" => "Bounded the query."}
      })
      |> Repo.insert!()

    list_response =
      conn
      |> authenticated(token)
      |> get(~p"/api/flights?status=succeeded&objective=reproduce&outcome=not_reproduced")
      |> json_response(200)

    assert [%{"id" => id, "session" => nil}] = list_response["data"]
    assert id == flight.id
    assert hd(list_response["data"])["objective"] == "reproduce"
    assert hd(list_response["data"])["objective_outcome"] == "not_reproduced"
    assert list_response["pagination"]["total_count"] == 1

    show_response =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/flights/#{flight.id}")
      |> json_response(200)

    assert show_response["data"]["session"]["source"]["base_revision"] == "abc123"
  end

  test "forbids collaborators", %{conn: conn} do
    {_user, token} = oauth_access_token!("flight-api-collaborator@example.com", :collaborator)

    conn = conn |> authenticated(token) |> get(~p"/api/flights")

    assert json_response(conn, 403) == %{"error" => "forbidden"}
  end

  defp authenticated(conn, token),
    do: put_req_header(conn, "authorization", "Bearer #{token.value}")

  defp oauth_access_token!(email, role) do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: email,
        provider: "test",
        provider_uid: email
      })

    {:ok, user} = Accounts.update_user_role(user, role)

    {:ok, client} =
      %Client{}
      |> Client.create_changeset(%{
        name: "Flight application programming interface test client",
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
        scope: "api",
        resource: "http://www.example.com/api",
        access_token_ttl: 60
      })
      |> Repo.insert()

    {user, token}
  end

  defp repository do
    {:ok, project} = Projects.create_project(%{name: "Flight application programming interface"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        owner: "tuist",
        name: "hive-#{System.unique_integer([:positive])}"
      })

    repository
  end
end
