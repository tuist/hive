defmodule HiveWeb.OpenGraphTest do
  use HiveWeb.ConnCase, async: true

  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Hive.Forage
  alias HiveWeb.AccountLive
  alias HiveWeb.ForageLive
  alias HiveWeb.OpenGraph
  alias HiveWeb.OpsLive
  alias HiveWeb.PageHTML

  defmodule EnabledStorage do
    def enabled?, do: true
    def configured?, do: true
  end

  defmodule DisabledStorage do
    def enabled?, do: false
    def configured?, do: false
  end

  defmodule LazyBrowser do
    def init(parent: parent) do
      send(parent, :browser_initialized)
      {:ok, %{parent: parent}}
    end

    def terminate(reason, %{parent: parent}) do
      send(parent, {:browser_terminated, reason})
      :ok
    end

    def navigate(%{parent: parent}, url, opts) do
      send(parent, {:browser_navigated, url, opts})
      :ok
    end

    def set_viewport(%{parent: parent}, width, height, opts) do
      send(parent, {:browser_viewport_set, width, height, opts})
      :ok
    end
  end

  defmodule FailingBrowser do
    def init(_opts), do: {:error, :devtools_timeout}
  end

  defp open_graph_data do
    %{
      description: "Description",
      section_label: "Forage",
      highlights: ["One", "Two", "Three"],
      id: "sample-page",
      path: "/sample",
      title: "Sample"
    }
  end

  test "path includes a stable signed card token" do
    data = open_graph_data()
    path = OpenGraph.path(data)
    token = token_from_path(path)

    assert OpenGraph.hash(data) != OpenGraph.hash(%{data | description: "Different copy"})
    assert path == OpenGraph.path(data)
    assert path =~ "/open-graph/card.jpg?token="
    assert OpenGraph.object_key(data) == "open-graph/cards/#{OpenGraph.hash(data)}.jpg"

    assert {:ok, %{id: "sample-page", path: "/sample", section_label: "Forage"}} =
             OpenGraph.verify_token(HiveWeb.Endpoint, token)
  end

  test "assigns include absolute social metadata" do
    data = open_graph_data()

    assert [
             open_graph: %{
               description: description,
               image: image,
               image_height: 1008,
               image_width: 1920,
               title: "Sample | Hive",
               twitter_card: "summary_large_image",
               url: url
             }
           ] = OpenGraph.assigns(data)

    assert description == data.description
    assert image =~ "/open-graph/card.jpg?token="
    assert url =~ data.path
  end

  test "verify_token rejects tampered card tokens" do
    token =
      open_graph_data()
      |> OpenGraph.path()
      |> token_from_path()
      |> Kernel.<>("tampered")

    assert {:error, :invalid} = OpenGraph.verify_token(HiveWeb.Endpoint, token)
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
      OpsLive.Slack.open_graph(),
      ForageLive.Index.open_graph(%{total: 3, open: 2, domains: 1}),
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
        generator: fn %{id: "sample-page", version: "v5"} -> "generated-jpeg" end,
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

  test "serve returns service unavailable when image generation fails", %{conn: conn} do
    log =
      capture_log(fn ->
        conn =
          OpenGraph.serve(conn, open_graph_data(),
            storage: DisabledStorage,
            generator: fn _data -> raise "renderer unavailable" end
          )

        assert response(conn, 503) == "OpenGraph image unavailable"
      end)

    assert log =~ "OpenGraph image generation failed"
  end

  test "browser pool uses the lazy OpenGraph browser implementation" do
    assert %{
             start:
               {Browse, :start_link,
                [
                  HiveWeb.OpenGraph.BrowserPool,
                  [implementation: HiveWeb.OpenGraph.Browser, pool_size: 2]
                ]}
           } = OpenGraph.browser_pool_child_spec()
  end

  test "lazy browser starts the delegate on first operation and reuses it" do
    {:ok, manager} = HiveWeb.OpenGraph.Browser.init(delegate: LazyBrowser, parent: self())

    refute_received :browser_initialized

    assert :ok = HiveWeb.OpenGraph.Browser.navigate(manager, "file:///card.html", [])
    assert :ok = HiveWeb.OpenGraph.Browser.set_viewport(manager, 1920, 1008, [])

    assert_receive :browser_initialized
    assert_receive {:browser_navigated, "file:///card.html", []}
    assert_receive {:browser_viewport_set, 1920, 1008, []}
    refute_received :browser_initialized

    assert :ok = HiveWeb.OpenGraph.Browser.terminate(:normal, manager)
    assert_receive {:browser_terminated, :normal}
  end

  test "lazy browser returns delegate startup errors without raising" do
    {:ok, manager} = HiveWeb.OpenGraph.Browser.init(delegate: FailingBrowser)

    assert {:error, :devtools_timeout} =
             HiveWeb.OpenGraph.Browser.navigate(manager, "file:///card.html", [])
  end

  test "browser pool starts even when the delegate cannot start" do
    assert {:ok, pool} =
             Browse.start_link(nil,
               implementation: HiveWeb.OpenGraph.Browser,
               delegate: FailingBrowser,
               pool_size: 1
             )

    assert {:error, :devtools_timeout} =
             Browse.checkout(pool, fn browser ->
               Browse.navigate(browser, "file:///card.html", [])
             end)

    GenServer.stop(pool)
  end

  test "render_html escapes page data and includes the card content" do
    html =
      OpenGraph.render_html(%{
        author: %{handle: "@unsafe", initials: "<u>"},
        description: ~s|Description with <script>alert("x")</script>|,
        section_label: "Forage",
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
             section_label: section_label,
             highlights: highlights,
             id: id,
             path: path,
             title: title
           } = data

    assert is_binary(description) and description != ""
    assert is_binary(section_label) and section_label != ""
    assert is_list(highlights) and highlights != []
    assert Enum.all?(highlights, &is_binary/1)
    assert is_binary(id) and id != ""
    assert is_binary(path) and String.starts_with?(path, "/")
    assert is_binary(title) and title != ""

    assert is_binary(OpenGraph.hash(data))
    assert OpenGraph.path(data) =~ "/open-graph/card.jpg?token="
    assert OpenGraph.object_key(data) =~ "open-graph/cards/"
    assert OpenGraph.render_html(data) =~ title

    assert [
             open_graph: %{
               description: ^description,
               image: image,
               image_height: 1008,
               image_width: 1920,
               title: meta_title,
               twitter_card: "summary_large_image",
               url: url
             }
           ] = OpenGraph.assigns(data)

    assert image =~ "/open-graph/card.jpg?token="
    assert meta_title =~ title
    assert url =~ path
  end

  defp token_from_path(path) do
    path
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
    |> Map.fetch!("token")
  end
end
