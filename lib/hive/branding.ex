defmodule Hive.Branding do
  @moduledoc """
  Per-instance branding: the name and logo the instance presents itself
  with across the dashboard, login screen, favicon, and OpenGraph cards.

  Hive ships with its own name and logo, which is what an unconfigured
  instance shows. A deployment that runs Hive under its own brand sets
  `HIVE_PRODUCT_NAME` and points `HIVE_LOGO_URL` at a publicly reachable
  image. The remote image is fetched once and cached in memory, so the
  OpenGraph card generator keeps embedding the logo instead of depending
  on the network while rendering.
  """

  @product_name "Hive"
  @logo_path "/images/logo.png"

  @doc "The name this instance presents itself with."
  def product_name(opts \\ []) do
    case config(opts, :product_name) do
      nil -> @product_name
      name -> name
    end
  end

  @doc """
  The logo to render in `<img>` and `<link rel="icon">` tags: either the
  bundled logo's static path or the configured absolute URL.
  """
  def logo_url(opts \\ []) do
    case config(opts, :logo_url) do
      nil -> @logo_path
      url -> url
    end
  end

  @doc "True when the instance replaced the bundled Hive logo."
  def custom_logo?(opts \\ []), do: logo_url(opts) != @logo_path

  @doc """
  The logo as a `data:` URI for embedding into generated images, or `nil`
  when it can't be read. A configured remote logo is fetched once and
  cached; a failed fetch falls back to the bundled logo.
  """
  def logo_data_uri(opts \\ []) do
    case logo_url(opts) do
      @logo_path -> bundled_logo_data_uri()
      url -> remote_logo_data_uri(url) || bundled_logo_data_uri()
    end
  end

  @doc """
  A value that changes whenever the rendered logo changes, for cache keys
  of artifacts that embed it. The bundled logo is keyed by its bytes; a
  configured logo by its URL, so instances don't pay a fetch per lookup.
  """
  def logo_cache_key(opts \\ []) do
    case logo_url(opts) do
      @logo_path -> bundled_logo_hash()
      url -> url
    end
  end

  defp remote_logo_data_uri(url) do
    case :persistent_term.get({__MODULE__, :logo, url}, :miss) do
      :miss -> url |> fetch_logo() |> cache_logo(url)
      cached -> cached
    end
  end

  defp fetch_logo(url) do
    case Req.get(url, receive_timeout: 5_000, retry: false) do
      {:ok, %Req.Response{status: 200, body: body} = response} when is_binary(body) ->
        "data:#{content_type(response)};base64,#{Base.encode64(body)}"

      _other ->
        nil
    end
  rescue
    _error -> nil
  end

  defp cache_logo(nil, _url), do: nil

  defp cache_logo(data_uri, url) do
    :persistent_term.put({__MODULE__, :logo, url}, data_uri)
    data_uri
  end

  defp content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [content_type | _rest] -> content_type |> String.split(";") |> hd() |> String.trim()
      [] -> "image/png"
    end
  end

  defp bundled_logo_data_uri do
    case File.read(bundled_logo_path()) do
      {:ok, logo} -> "data:image/png;base64,#{Base.encode64(logo)}"
      {:error, _reason} -> nil
    end
  end

  defp bundled_logo_hash do
    case File.read(bundled_logo_path()) do
      {:ok, logo} ->
        :sha256
        |> :crypto.hash(logo)
        |> Base.url_encode64(padding: false)

      {:error, _reason} ->
        "missing-logo"
    end
  end

  defp bundled_logo_path, do: Application.app_dir(:hive, "priv/static#{@logo_path}")

  defp config(opts, key) do
    opts
    |> Keyword.get_lazy(key, fn ->
      :hive |> Application.get_env(:branding, []) |> Keyword.get(key)
    end)
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end
end
