defmodule HiveWeb.OpenGraph do
  @moduledoc """
  Runtime OpenGraph image metadata and lazy browser rendering.
  """

  import Plug.Conn

  alias Hive.Auth
  alias Hive.Forage
  alias Hive.ObjectStorage
  alias HiveWeb.Endpoint

  @browser_pool HiveWeb.OpenGraph.BrowserPool
  @browser_supervisor Hive.OpenGraphSupervisor
  @content_type "image/jpeg"
  @height 1080
  @quality 95
  @version "v2"
  @width 1920

  def content_type, do: @content_type
  def height, do: @height
  def width, do: @width

  def login_page do
    %{
      description:
        "Sign in to submit public ideas and help turn product signals into actionable work.",
      eyebrow: Auth.product_name(),
      highlights: ["OIDC sign-in", "Public by default", "Organization-aware"],
      id: "login",
      path: "/login",
      title: "Log in to #{Auth.product_name()}"
    }
  end

  def feature_requests_page(feature_requests) do
    stats = feature_request_stats(feature_requests)

    %{
      description: "Public product ideas submitted by authenticated users.",
      eyebrow: "Forage",
      highlights: [
        "#{stats.total} total requests",
        "#{stats.open} open",
        "#{stats.contributors} contributors"
      ],
      id: "forage-feature-requests",
      path: "/forage/feature-requests",
      title: "Feature requests"
    }
  end

  def new_feature_request_page do
    %{
      description: "Capture a public idea that can become workable product direction.",
      eyebrow: "Forage",
      highlights: ["Public ideas", "Actionable context", "Contributor signal"],
      id: "forage-feature-requests-new",
      path: "/forage/feature-requests/new",
      title: "New feature request"
    }
  end

  def forage_source_page(source) do
    %{
      description: source.description,
      eyebrow: "Forage",
      highlights: source_highlights(source),
      id: "forage-#{source_slug(source)}",
      path: source.path,
      title: source.label
    }
  end

  def page("login"), do: {:ok, login_page()}

  def page("forage-feature-requests") do
    {:ok, feature_requests_page(Forage.list_feature_requests())}
  end

  def page("forage-feature-requests-new"), do: {:ok, new_feature_request_page()}

  def page("forage-" <> source_slug) do
    Forage.sources()
    |> Enum.find(&(source_slug(&1) == source_slug))
    |> case do
      nil -> :error
      source -> {:ok, forage_source_page(source)}
    end
  end

  def page(_page_id), do: :error

  def assigns(data) do
    [
      open_graph: %{
        description: data.description,
        image: absolute_url(path(data)),
        image_height: @height,
        image_width: @width,
        title: meta_title(data),
        twitter_card: "summary_large_image",
        url: absolute_url(data.path)
      }
    ]
  end

  def path(data), do: "/open-graph/#{data.id}/#{hash(data)}"

  def object_key(data), do: "open-graph/#{data.id}/#{hash(data)}.jpg"

  def hash(data) do
    :sha256
    |> :crypto.hash(
      :erlang.term_to_binary([
        @version,
        @content_type,
        @width,
        @height,
        Auth.product_name(),
        logo_hash(),
        normalize(data)
      ])
    )
    |> Base.url_encode64(padding: false)
  end

  def valid_hash?(data, hash), do: hash(data) == hash

  def serve(conn, data, opts \\ []) do
    storage = Keyword.get(opts, :storage, ObjectStorage)

    if storage_enabled?(storage) do
      serve_with_storage(conn, data, storage, opts)
    else
      generate_and_send(conn, data, storage, opts, store?: false)
    end
  end

  def generate(data) do
    html = render_html(data)

    case render_with_browser(html) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "failed to generate OpenGraph image: #{inspect(reason)}"
    end
  end

  def render_html(data) do
    highlights =
      data.highlights
      |> Enum.take(3)
      |> Enum.map_join("\n", fn highlight ->
        ~s(<li><span>#{escape(highlight)}</span></li>)
      end)

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=#{@width}, height=#{@height}" />
        <style>
          * {
            box-sizing: border-box;
          }

          html,
          body {
            margin: 0;
            width: #{@width}px;
            height: #{@height}px;
            overflow: hidden;
            font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            color: #252a33;
            background: #f5f7fb;
          }

          body {
            display: grid;
            place-items: stretch;
          }

          .card {
            position: relative;
            width: #{@width}px;
            height: #{@height}px;
            padding: 96px;
            background:
              linear-gradient(90deg, rgba(119, 90, 255, 0.16) 0, rgba(119, 90, 255, 0) 34%),
              linear-gradient(180deg, #ffffff 0, #f8fafc 100%);
          }

          .card::before {
            position: absolute;
            inset: 0;
            content: "";
            background-image:
              linear-gradient(rgba(37, 42, 51, 0.05) 1px, transparent 1px),
              linear-gradient(90deg, rgba(37, 42, 51, 0.05) 1px, transparent 1px);
            background-size: 56px 56px;
            mask-image: linear-gradient(180deg, rgba(0, 0, 0, 0.7), transparent 74%);
          }

          .accent {
            position: absolute;
            inset: 0 auto 0 0;
            width: 18px;
            background: linear-gradient(180deg, #775aff 0%, #49beaa 58%, #eeb44f 100%);
          }

          .content {
            position: relative;
            z-index: 1;
            display: flex;
            flex-direction: column;
            height: 100%;
          }

          .brand {
            display: flex;
            align-items: center;
            gap: 28px;
            min-height: 84px;
            color: #333948;
            font-size: 34px;
            font-weight: 650;
          }

          .brand img {
            width: 76px;
            height: 76px;
            object-fit: contain;
          }

          .main {
            margin-top: 112px;
            max-width: 1380px;
          }

          .eyebrow {
            margin: 0 0 34px;
            color: #5a6274;
            font-size: 42px;
            font-weight: 700;
            letter-spacing: 0;
          }

          h1 {
            margin: 0;
            max-width: 1430px;
            color: #252a33;
            font-size: 122px;
            font-weight: 760;
            letter-spacing: 0;
            line-height: 1.02;
            overflow-wrap: anywhere;
          }

          .description {
            margin: 44px 0 0;
            max-width: 1270px;
            color: #555f72;
            font-size: 48px;
            font-weight: 450;
            line-height: 1.26;
          }

          .footer {
            display: flex;
            align-items: end;
            justify-content: space-between;
            gap: 64px;
            margin-top: auto;
          }

          ul {
            display: flex;
            flex-wrap: wrap;
            gap: 22px;
            max-width: 1320px;
            margin: 0;
            padding: 0;
            list-style: none;
          }

          li {
            display: flex;
            align-items: center;
            min-height: 72px;
            max-width: 420px;
            padding: 0 28px;
            border: 1px solid rgba(37, 42, 51, 0.1);
            border-radius: 999px;
            background: rgba(255, 255, 255, 0.72);
            color: #333948;
            font-size: 30px;
            font-weight: 650;
            overflow: hidden;
          }

          li span {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }

          .path {
            color: #788296;
            font-size: 28px;
            font-weight: 560;
            white-space: nowrap;
          }
        </style>
      </head>
      <body>
        <main class="card">
          <div class="accent"></div>
          <section class="content">
            <header class="brand">
              #{logo_markup()}
              <span>#{escape(Auth.product_name())}</span>
            </header>

            <section class="main">
              <p class="eyebrow">#{escape(data.eyebrow)}</p>
              <h1>#{escape(data.title)}</h1>
              <p class="description">#{escape(data.description)}</p>
            </section>

            <footer class="footer">
              <ul>
                #{highlights}
              </ul>
              <span class="path">#{escape(data.path)}</span>
            </footer>
          </section>
        </main>
      </body>
    </html>
    """
  end

  defp serve_with_storage(conn, data, storage, opts) do
    key = object_key(data)
    head_object = Keyword.get(opts, :head_object, &storage.head_object/1)

    case head_object.(key) do
      {:ok, _response} ->
        stream_stored(conn, key, storage, opts)

      {:error, _reason} ->
        generate_and_send(conn, data, storage, opts, store?: true)
    end
  end

  defp stream_stored(conn, key, storage, opts) do
    stream_object = Keyword.get(opts, :stream_object, &storage.stream_object/2)
    conn_ref = {__MODULE__, make_ref()}

    conn =
      conn
      |> put_common_headers()
      |> send_chunked(200)

    Process.put(conn_ref, conn)

    try do
      stream_object.(key, fn chunk ->
        case chunk(Process.get(conn_ref), chunk) do
          {:ok, conn} ->
            Process.put(conn_ref, conn)
            :ok

          {:error, :closed} ->
            :halt
        end
      end)

      Process.get(conn_ref)
    after
      Process.delete(conn_ref)
    end
  end

  defp generate_and_send(conn, data, storage, opts, store?: store?) do
    generator = Keyword.get(opts, :generator, &generate/1)
    body = generator.(data)

    if store? do
      put_object = Keyword.get(opts, :put_object, &storage.put_object/3)
      put_object.(object_key(data), body, content_type: @content_type)
    end

    conn
    |> put_common_headers()
    |> send_resp(200, body)
  end

  defp put_common_headers(conn) do
    conn
    |> put_resp_header("content-type", @content_type)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
  end

  defp storage_enabled?(storage) do
    function_exported?(storage, :enabled?, 0) and storage.enabled?() and
      function_exported?(storage, :configured?, 0) and storage.configured?()
  end

  defp render_with_browser(html) do
    with :ok <- ensure_browser_pool_started() do
      Carta.render(@browser_pool, html, width: @width, height: @height, quality: @quality)
    end
  end

  defp ensure_browser_pool_started do
    cond do
      Process.whereis(@browser_pool) ->
        :ok

      is_nil(Process.whereis(@browser_supervisor)) ->
        {:error, :browser_supervisor_not_started}

      true ->
        @browser_pool
        |> Browse.child_spec(browser_pool_opts())
        |> then(&DynamicSupervisor.start_child(@browser_supervisor, &1))
        |> case do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp browser_pool_opts do
    [
      implementation: BrowseChrome.Browser,
      pool_size: browser_pool_size()
    ]
    |> maybe_put_chrome_path()
  end

  defp browser_pool_size do
    :hive
    |> Application.get_env(:open_graph, [])
    |> Keyword.get(:browser_pool_size, 2)
    |> case do
      pool_size when is_integer(pool_size) and pool_size > 0 -> pool_size
      _other -> 2
    end
  end

  defp maybe_put_chrome_path(opts) do
    case Application.get_env(:hive, :open_graph, [])[:chrome_path] do
      path when is_binary(path) and path != "" -> Keyword.put(opts, :chrome_path, path)
      _other -> opts
    end
  end

  defp absolute_url(path), do: Endpoint.url() <> path

  defp meta_title(%{title: title}), do: "#{title} | #{Auth.product_name()}"

  defp logo_markup do
    case logo_data_uri() do
      nil -> ""
      data_uri -> ~s(<img src="#{data_uri}" alt="" />)
    end
  end

  defp logo_data_uri do
    case File.read(logo_path()) do
      {:ok, logo} -> "data:image/png;base64,#{Base.encode64(logo)}"
      {:error, _reason} -> nil
    end
  end

  defp logo_hash do
    case File.read(logo_path()) do
      {:ok, logo} ->
        :sha256
        |> :crypto.hash(logo)
        |> Base.url_encode64(padding: false)

      {:error, _reason} ->
        "missing-logo"
    end
  end

  defp logo_path, do: Application.app_dir(:hive, "priv/static/images/logo.png")

  defp escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp feature_request_stats(feature_requests) do
    %{
      total: length(feature_requests),
      open: Enum.count(feature_requests, &(&1.status == :open)),
      contributors:
        feature_requests
        |> Enum.map(& &1.user_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()
    }
  end

  defp source_highlights(source) do
    [
      source_visibility(source.visibility),
      if(source.creatable?, do: "Contributor submissions", else: "Read-only signals"),
      "Forage source"
    ]
  end

  defp source_visibility(:organization), do: "Organization visible"
  defp source_visibility(_visibility), do: "Public source"

  defp source_slug(source) do
    source.id
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp normalize(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {normalize_key(key), normalize(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: to_string(key)
end
