defmodule HiveWeb.Api.V1.DropDigestControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Drops.WeeklyDigest

  @resource "http://www.example.com/api/v1"

  test "lists, searches, paginates, and gets published weekly digests", %{conn: conn} do
    {token, _user} = mobile_access_token!("drop-digests@example.com", "mobile", @resource)

    wanted =
      insert_digest!(%{
        week_start: ~D[2026-07-06],
        week_end: ~D[2026-07-10],
        title: "The mobile feedback loop"
      })

    insert_digest!(%{
      week_start: ~D[2026-06-29],
      week_end: ~D[2026-07-03],
      title: "A quieter server week"
    })

    response =
      conn
      |> authorize(token)
      |> get(~p"/api/v1/drops/digests?query=mobile&page=1&page_size=1")
      |> json_response(200)

    assert [
             %{
               "week_start" => "2026-07-06",
               "title" => "The mobile feedback loop",
               "drop_count" => 2
             }
           ] = response["data"]

    assert response["pagination"]["total_count"] == 1

    show_conn =
      build_conn()
      |> authorize(token)
      |> get("/api/v1/drops/digests/#{wanted.week_start}")

    assert json_response(show_conn, 200)["data"]["body"] =~ "connected narration"
  end

  test "returns not found for an unpublished week", %{conn: conn} do
    {token, _user} = mobile_access_token!("digest-missing@example.com", "mobile", @resource)

    response =
      conn
      |> authorize(token)
      |> get(~p"/api/v1/drops/digests/2025-01-06")
      |> json_response(404)

    assert response["error"] == "not_found"
  end

  defp insert_digest!(overrides) do
    attrs =
      Map.merge(
        %{
          status: :published,
          title: "Weekly edition",
          summary: "A connected summary.",
          body: "A connected narration.",
          drop_ids: [Ecto.UUID.generate(), Ecto.UUID.generate()],
          published_at: ~U[2026-07-10 17:00:00Z]
        },
        overrides
      )

    %WeeklyDigest{}
    |> WeeklyDigest.changeset(attrs)
    |> Hive.Repo.insert!()
  end

  defp authorize(conn, token),
    do: put_req_header(conn, "authorization", "Bearer #{token.value}")
end
