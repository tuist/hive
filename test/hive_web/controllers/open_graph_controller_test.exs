defmodule HiveWeb.OpenGraphControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Specs
  alias HiveWeb.OpenGraph
  alias HiveWeb.SpecLive

  test "GET /open-graph/:page_id/:hash returns the image response", %{conn: conn} do
    parent = self()

    stub(OpenGraph, :valid_hash?, fn %{id: "login"} = data, "valid" ->
      send(parent, {:data, data})
      true
    end)

    stub(OpenGraph, :serve, fn conn, %{id: "login"} ->
      conn
      |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
      |> Plug.Conn.send_resp(200, "jpeg")
    end)

    conn = get(conn, ~p"/open-graph/login/valid")

    assert response(conn, 200) == "jpeg"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert_received {:data, %{path: "/login", title: "Log in to Hive"}}
  end

  test "GET /open-graph/:page_id/:hash rejects stale hashes", %{conn: conn} do
    conn = get(conn, ~p"/open-graph/login/stale")

    assert response(conn, 404) == "Not found"
  end

  test "GET /open-graph/specs/:hash uses the default draft specs data", %{conn: conn} do
    {_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, _draft} =
      Specs.create_spec(%{"title" => "Draft proposal", "body" => "Initial proposal."}, user)

    {:ok, _approved} =
      Specs.create_spec(
        %{"title" => "Approved proposal", "body" => "Approved proposal.", "status" => "approved"},
        user
      )

    data = SpecLive.Index.open_graph(Specs.list_specs(status: :draft))

    stub(OpenGraph, :serve, fn conn,
                               %{id: "specs", highlights: ["1 specs", "1 drafts", "0 shipped"]} ->
      Plug.Conn.send_resp(conn, 200, "jpeg")
    end)

    conn = get(conn, OpenGraph.path(data))

    assert response(conn, 200) == "jpeg"
  end

  test "GET /open-graph/spec-:number/:hash rejects private specs for anonymous users", %{
    conn: conn
  } do
    {_signed_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Private proposal",
          "body" => "Initial proposal.",
          "visibility" => "private"
        },
        user
      )

    data = SpecLive.Show.open_graph(Specs.get_spec!(spec.id))

    conn = get(conn, OpenGraph.path(data))

    assert response(conn, 404) == "Not found"
  end

  test "GET /open-graph/spec-:number/:hash serves private specs for members", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, spec} =
      Specs.create_spec(
        %{
          "title" => "Private proposal",
          "body" => "Initial proposal.",
          "visibility" => "private"
        },
        user
      )

    data = SpecLive.Show.open_graph(Specs.get_spec!(spec.id))
    spec_id = "spec-#{spec.number}"

    stub(OpenGraph, :serve, fn conn, %{id: ^spec_id} ->
      Plug.Conn.send_resp(conn, 200, "jpeg")
    end)

    conn = get(conn, OpenGraph.path(data))

    assert response(conn, 200) == "jpeg"
  end
end
