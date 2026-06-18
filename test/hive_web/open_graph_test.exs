defmodule HiveWeb.OpenGraphTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage
  alias HiveWeb.AccountLive
  alias HiveWeb.ForageLive
  alias HiveWeb.OpenGraph
  alias HiveWeb.PageHTML

  defmodule EnabledStorage do
    def enabled?, do: true
    def configured?, do: true
  end

  defmodule DisabledStorage do
    def enabled?, do: false
    def configured?, do: false
  end

  defp open_graph_data do
    %{
      description: "Description",
      eyebrow: "Forage",
      highlights: ["One", "Two", "Three"],
      id: "sample-page",
      path: "/sample",
      title: "Sample"
    }
  end

  test "hash changes when rendered data changes" do
    data = open_graph_data()

    assert OpenGraph.hash(data) != OpenGraph.hash(%{data | description: "Different copy"})
    assert OpenGraph.path(data) == "/open-graph/#{data.id}/#{OpenGraph.hash(data)}"
    assert OpenGraph.object_key(data) == "open-graph/#{data.id}/#{OpenGraph.hash(data)}.jpg"
  end

  test "assigns include absolute social metadata" do
    data = open_graph_data()

    assert [
             open_graph: %{
               description: description,
               image: image,
               image_height: 1080,
               image_width: 1920,
               title: "Sample | Hive",
               twitter_card: "summary_large_image",
               url: url
             }
           ] = OpenGraph.assigns(data)

    assert description == data.description
    assert image =~ OpenGraph.path(data)
    assert url =~ data.path
  end

  test "page OpenGraph data is compatible with the renderer contract" do
    feature_requests = [
      %{status: :open, user_id: "alice"},
      %{status: :open, user_id: "alice"},
      %{status: :closed, user_id: nil}
    ]

    page_data = [
      PageHTML.open_graph(),
      AccountLive.Identities.open_graph(),
      ForageLive.Index.open_graph(%{total: 3, open: 2, meadows: 1}),
      ForageLive.FeatureRequests.open_graph(feature_requests),
      ForageLive.NewFeatureRequest.open_graph()
      | Enum.map(Forage.sources(), &ForageLive.Placeholder.open_graph/1)
    ]

    Enum.each(page_data, &assert_open_graph_contract/1)
  end

  test "serve generates and stores the image when object storage misses", %{conn: conn} do
    data = open_graph_data()
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
    data = open_graph_data()
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
      OpenGraph.serve(conn, open_graph_data(),
        storage: DisabledStorage,
        generator: fn _data -> "generated-jpeg" end
      )

    assert response(conn, 200) == "generated-jpeg"
  end

  test "render_html escapes page data and includes the card content" do
    html =
      OpenGraph.render_html(%{
        author: %{handle: "@unsafe", initials: "<u>"},
        description: ~s|Description with <script>alert("x")</script>|,
        eyebrow: "Forage",
        highlights: ["<unsafe>", "Public source"],
        id: "forage-unsafe",
        path: "/forage/unsafe",
        title: "Unsafe <title>"
      })

    assert html =~ "Unsafe &lt;title&gt;"
    assert html =~ "@unsafe"
    assert html =~ "&lt;u&gt;"
    assert html =~ "&lt;unsafe&gt;"
    assert html =~ "Description with &lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"
    assert html =~ "<main class=\"card\">"
  end

  defp assert_open_graph_contract(data) do
    assert %{
             description: description,
             eyebrow: eyebrow,
             highlights: highlights,
             id: id,
             path: path,
             title: title
           } = data

    assert is_binary(description) and description != ""
    assert is_binary(eyebrow) and eyebrow != ""
    assert is_list(highlights) and highlights != []
    assert Enum.all?(highlights, &is_binary/1)
    assert is_binary(id) and id != ""
    assert is_binary(path) and String.starts_with?(path, "/")
    assert is_binary(title) and title != ""

    assert is_binary(OpenGraph.hash(data))
    assert OpenGraph.path(data) =~ "/open-graph/#{id}/"
    assert OpenGraph.object_key(data) =~ "open-graph/#{id}/"
    assert OpenGraph.render_html(data) =~ title

    assert [
             open_graph: %{
               description: ^description,
               image: image,
               image_height: 1080,
               image_width: 1920,
               title: meta_title,
               twitter_card: "summary_large_image",
               url: url
             }
           ] = OpenGraph.assigns(data)

    assert image =~ OpenGraph.path(data)
    assert meta_title =~ title
    assert url =~ path
  end
end
