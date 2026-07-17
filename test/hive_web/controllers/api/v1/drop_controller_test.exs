defmodule HiveWeb.Api.V1.DropControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Domains
  alias Hive.Drops
  alias Hive.Projects

  @resource "http://www.example.com/api/v1"

  test "lists, searches, paginates, and gets visible drops", %{conn: conn} do
    {token, _user} = mobile_access_token!("drops@example.com", "mobile", @resource)
    domain = public_domain!()

    wanted =
      insert_drop!(domain, %{
        title: "Mobile Drops timeline",
        body: "Read shipped updates in the native application."
      })

    insert_drop!(domain, %{title: "Server release", body: "Read this on the dashboard."})

    response =
      conn
      |> authorize(token)
      |> get(~p"/api/v1/drops?query=Mobile&page=1&page_size=1")
      |> json_response(200)

    assert [
             %{
               "number" => number,
               "title" => "Mobile Drops timeline",
               "source_type" => "github_release"
             }
           ] = response["data"]

    assert number == wanted.number

    assert response["pagination"] == %{
             "page" => 1,
             "page_size" => 1,
             "total_count" => 1,
             "total_pages" => 1
           }

    show_conn = build_conn() |> authorize(token) |> get("/api/v1/drops/#{wanted.number}")
    assert json_response(show_conn, 200)["data"]["body"] =~ "native application"
  end

  test "returns plain text for markup imported from feeds", %{conn: conn} do
    {token, _user} = mobile_access_token!("rss-drops@example.com", "mobile", @resource)
    domain = public_domain!()

    drop =
      insert_drop!(domain, %{
        source_type: :rss,
        body: "<p>Native readers get <strong>safe text</strong>.</p>"
      })

    response =
      conn
      |> authorize(token)
      |> get("/api/v1/drops/#{drop.number}")
      |> json_response(200)

    assert response["data"]["body"] == "Native readers get safe text.\n"
  end

  test "returns not found for an unknown drop", %{conn: conn} do
    {token, _user} = mobile_access_token!("drop-missing@example.com", "mobile", @resource)

    response = conn |> authorize(token) |> get(~p"/api/v1/drops/999999") |> json_response(404)
    assert response["error"] == "not_found"
  end

  defp public_domain! do
    suffix = System.unique_integer([:positive])
    {:ok, project} = Projects.create_project(%{name: "Drops project #{suffix}"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Drops domain #{suffix}",
        project_id: project.id,
        visibility: "public"
      })

    domain
  end

  defp insert_drop!(domain, overrides) do
    suffix = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          source_type: :github_release,
          external_id: "mobile-drop-#{suffix}",
          title: "Drop #{suffix}",
          body: "Body",
          url: "https://example.com/releases/#{suffix}",
          version: "1.#{suffix}.0",
          published_at: ~U[2026-07-16 12:00:00Z]
        },
        overrides
      )

    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end

  defp authorize(conn, token),
    do: put_req_header(conn, "authorization", "Bearer #{token.value}")
end
