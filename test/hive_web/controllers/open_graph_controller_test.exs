defmodule HiveWeb.OpenGraphControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Specs
  alias HiveWeb.OpenGraph
  alias HiveWeb.PageHTML
  alias HiveWeb.SpecLive

  test "GET /open-graph/card.jpg returns the image response for a signed card", %{conn: conn} do
    parent = self()
    data = PageHTML.open_graph()
    image_path = OpenGraph.path(data)

    stub(OpenGraph, :serve, fn conn, %{id: "login"} = data ->
      send(parent, {:data, data})

      conn
      |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
      |> Plug.Conn.send_resp(200, "jpeg")
    end)

    conn = get(conn, image_path)

    assert response(conn, 200) == "jpeg"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert_received {:data, %{path: "/login", title: "Log in to Hive"}}
  end

  test "GET /open-graph/card.jpg rejects invalid tokens", %{conn: conn} do
    conn = get(conn, ~p"/open-graph/card.jpg?token=invalid")

    assert response(conn, 404) == "Not found"
  end

  test "GET /open-graph/card.jpg rejects missing tokens", %{conn: conn} do
    conn = get(conn, ~p"/open-graph/card.jpg")

    assert response(conn, 404) == "Not found"
  end

  test "GET /open-graph/card.jpg uses the default specs data", %{conn: conn} do
    {_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, _draft} =
      Specs.create_spec(%{"title" => "Draft proposal", "body" => "Initial proposal."}, user)

    {:ok, _approved} =
      Specs.create_spec(
        %{"title" => "Approved proposal", "body" => "Approved proposal.", "status" => "approved"},
        user
      )

    data = SpecLive.Index.open_graph(Specs.list_specs())

    stub(OpenGraph, :serve, fn conn,
                               %{id: "specs", highlights: ["2 specs", "1 drafts", "0 shipped"]} ->
      Plug.Conn.send_resp(conn, 200, "jpeg")
    end)

    conn = get(conn, OpenGraph.path(data))

    assert response(conn, 200) == "jpeg"
  end

  test "GET /open-graph/card.jpg serves the image advertised by the specs page", %{
    conn: conn
  } do
    {_conn, user} = sign_in(conn, "alice@example.com")

    {:ok, _draft} =
      Specs.create_spec(%{"title" => "Draft proposal", "body" => "Initial proposal."}, user)

    {:ok, _approved} =
      Specs.create_spec(
        %{"title" => "Approved proposal", "body" => "Approved proposal.", "status" => "approved"},
        user
      )

    html = conn |> get(~p"/specs") |> html_response(200)
    image_path = advertised_open_graph_image_path(html)

    stub(OpenGraph, :serve, fn conn,
                               %{id: "specs", highlights: ["2 specs", "1 drafts", "0 shipped"]} ->
      Plug.Conn.send_resp(conn, 200, "jpeg")
    end)

    conn = get(conn, image_path)

    assert response(conn, 200) == "jpeg"
  end

  test "GET /open-graph/card.jpg serves signed spec cards", %{conn: conn} do
    {_conn, user} = sign_in(conn, "alice@example.com")

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

  defp advertised_open_graph_image_path(html) do
    [_, image] = Regex.run(~r/property="og:image" content="[^"]+(\/open-graph\/[^"]+)"/, html)
    image
  end
end
