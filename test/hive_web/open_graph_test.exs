defmodule HiveWeb.OpenGraphTest do
  use HiveWeb.ConnCase, async: true

  alias HiveWeb.OpenGraph

  defmodule EnabledStorage do
    def enabled?, do: true
    def configured?, do: true
  end

  defmodule DisabledStorage do
    def enabled?, do: false
    def configured?, do: false
  end

  test "hash changes when rendered data changes" do
    data = OpenGraph.login_page()

    assert OpenGraph.hash(data) != OpenGraph.hash(%{data | description: "Different copy"})
    assert OpenGraph.path(data) == "/open-graph/#{data.id}/#{OpenGraph.hash(data)}"
    assert OpenGraph.object_key(data) == "open-graph/#{data.id}/#{OpenGraph.hash(data)}.jpg"
  end

  test "assigns include absolute social metadata" do
    data = OpenGraph.login_page()

    assert [
             open_graph: %{
               description: description,
               image: image,
               image_height: 1080,
               image_width: 1920,
               title: "Log in to Hive | Hive",
               twitter_card: "summary_large_image",
               url: url
             }
           ] = OpenGraph.assigns(data)

    assert description == data.description
    assert image =~ OpenGraph.path(data)
    assert url =~ data.path
  end

  test "serve generates and stores the image when object storage misses", %{conn: conn} do
    data = OpenGraph.login_page()
    parent = self()

    conn =
      OpenGraph.serve(conn, data,
        storage: EnabledStorage,
        head_object: fn key ->
          send(parent, {:head, key})
          {:error, {:unexpected_status, 404, ""}}
        end,
        generator: fn ^data -> "generated-jpeg" end,
        put_object: fn key, body, opts ->
          send(parent, {:put, key, body, opts})
          {:ok, %{status: 200}}
        end
      )

    assert response(conn, 200) == "generated-jpeg"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert_received {:head, key}
    assert_received {:put, ^key, "generated-jpeg", [content_type: "image/jpeg"]}
  end

  test "serve streams an existing object storage image", %{conn: conn} do
    data = OpenGraph.login_page()
    parent = self()

    conn =
      OpenGraph.serve(conn, data,
        storage: EnabledStorage,
        head_object: fn key ->
          send(parent, {:head, key})
          {:ok, %{status: 200}}
        end,
        stream_object: fn key, stream ->
          send(parent, {:stream, key})
          assert stream.("stored") == :ok
          assert stream.("-jpeg") == :ok
          {:ok, %{status: 200}}
        end,
        generator: fn _data -> flunk("cache hits should not generate") end
      )

    assert response(conn, 200) == "stored-jpeg"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert_received {:head, key}
    assert_received {:stream, ^key}
  end

  test "serve generates without storing when object storage is disabled", %{conn: conn} do
    conn =
      OpenGraph.serve(conn, OpenGraph.login_page(),
        storage: DisabledStorage,
        generator: fn _data -> "generated-jpeg" end
      )

    assert response(conn, 200) == "generated-jpeg"
  end

  test "render_html escapes page data and includes the card content" do
    html =
      OpenGraph.render_html(%{
        description: ~s|Description with <script>alert("x")</script>|,
        eyebrow: "Forage",
        highlights: ["<unsafe>", "Public source"],
        id: "forage-unsafe",
        path: "/forage/unsafe",
        title: "Unsafe <title>"
      })

    assert html =~ "Unsafe &lt;title&gt;"
    assert html =~ "&lt;unsafe&gt;"
    assert html =~ "Description with &lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"
    assert html =~ "<main class=\"card\">"
  end
end
