defmodule Hive.ObjectStorage do
  @moduledoc """
  S3-compatible object storage client.

  Hive supports S3-compatible storage through environment variables. The
  implementation stays generic so self-hosted deployments can point at any
  compatible endpoint.
  """

  alias AWSAuth.Credentials

  @service "s3"
  @required_s3_keys [:bucket, :region, :endpoint_url, :access_key_id, :secret_access_key]
  @config_keys @required_s3_keys ++ [:public_base_url, :force_path_style]

  defstruct @config_keys

  def put_object(key, body, opts \\ []) when is_binary(key) and is_binary(body) do
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    request(:put, key,
      body: body,
      headers: [{"content-type", content_type}],
      config: Keyword.get(opts, :config),
      request: Keyword.get(opts, :request, &Req.request/1),
      success_statuses: [200, 201, 204]
    )
  end

  def get_object(key, opts \\ []) when is_binary(key) do
    with {:ok, response} <- request(:get, key, Keyword.put(opts, :success_statuses, [200])) do
      {:ok,
       %{
         body: response.body,
         content_type: content_type(response.headers),
         key: key
       }}
    end
  end

  def stream_object(key, chunk_fun, opts \\ [])
      when is_binary(key) and is_function(chunk_fun, 1) do
    request(:get, key,
      config: Keyword.get(opts, :config),
      request: Keyword.get(opts, :request, &Req.request/1),
      stream: chunk_fun,
      success_statuses: [200]
    )
  end

  def head_object(key, opts \\ []) when is_binary(key) do
    request(:head, key, Keyword.put(opts, :success_statuses, [200]))
  end

  def delete_object(key, opts \\ []) when is_binary(key) do
    request(:delete, key, Keyword.put(opts, :success_statuses, [200, 202, 204]))
  end

  def public_url(key, opts \\ []) when is_binary(key) do
    config = config!(opts)

    if present?(config.public_base_url) do
      {:ok, join_url(config.public_base_url, key)}
    else
      {:ok, object_url(config, key)}
    end
  end

  @doc "Returns the configured object storage provider."
  def provider do
    :hive
    |> Application.get_env(:object_storage, [])
    |> Keyword.get(:provider, :none)
  end

  @doc "True when an object storage provider is enabled."
  def enabled?, do: provider() != :none

  def configured? do
    match?({:ok, _config}, config())
  end

  @doc "Returns the configured bucket name, or nil when storage is unconfigured."
  def bucket do
    case config() do
      {:ok, config} -> config.bucket
      _other -> nil
    end
  end

  def config do
    case Application.get_env(:hive, :object_storage, []) do
      [provider: :s3, s3: s3] -> config_from_s3(s3)
      _other -> {:error, :disabled}
    end
  end

  @doc """
  Returns a validated S3 configuration.

  Returns `:disabled` when no provider is enabled, `{:ok, config}` when
  all required S3 fields are present, or `{:error, {:missing, keys}}`
  when S3 is enabled but incomplete.
  """
  def s3_config do
    :hive
    |> Application.get_env(:object_storage, [])
    |> s3_config()
  end

  def s3_config(config) do
    case Keyword.get(config, :provider, :none) do
      :none ->
        :disabled

      :s3 ->
        s3 = Keyword.get(config, :s3, [])

        missing =
          @required_s3_keys
          |> Enum.reject(fn key -> present?(Keyword.get(s3, key)) end)

        if missing == [] do
          {:ok, s3 |> Keyword.take(@config_keys) |> Map.new()}
        else
          {:error, {:missing, missing}}
        end
    end
  end

  @doc "Returns the public, non-secret pieces of the S3 configuration."
  def public_s3_config do
    case s3_config() do
      {:ok, config} ->
        Map.drop(config, [:access_key_id, :secret_access_key])

      other ->
        other
    end
  end

  defp request(method, key, opts) do
    config = config!(opts)
    body = Keyword.get(opts, :body, "")
    headers = Keyword.get(opts, :headers, [])
    success_statuses = Keyword.fetch!(opts, :success_statuses)
    url = object_url(config, key)
    stream = Keyword.get(opts, :stream)

    request = [
      method: method,
      url: url,
      body: body,
      headers: signed_headers(config, method, url, body, headers)
    ]

    request =
      if stream do
        Keyword.put(request, :into, stream_into(stream))
      else
        request
      end

    request_fun = Keyword.get(opts, :request, &Req.request/1)

    case request_fun.(request) do
      {:ok, %{status: status} = response} ->
        if status in success_statuses do
          {:ok, response}
        else
          {:error, {:unexpected_status, status, Map.get(response, :body)}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stream_into(stream) do
    fn {:data, data}, {req, resp} ->
      case stream.(data) do
        :ok -> {:cont, {req, resp}}
        :halt -> {:halt, {req, resp}}
      end
    end
  end

  defp signed_headers(%__MODULE__{} = config, method, url, body, headers) do
    credentials = %Credentials{
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    }

    AWSAuth.sign_authorization_header(
      credentials,
      method |> to_string() |> String.upcase(),
      url,
      @service,
      headers: normalize_headers(headers),
      payload: body,
      region: config.region,
      return_format: :list
    )
  end

  defp normalize_headers(headers) do
    Map.new(headers, fn {name, value} ->
      {name |> to_string() |> String.downcase(), canonical_header_value(value)}
    end)
  end

  defp canonical_header_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp content_type(headers) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(name) ->
        if String.downcase(name) == "content-type", do: value

      _other ->
        nil
    end)
  end

  defp object_url(%__MODULE__{} = config, key) do
    config.endpoint_url
    |> String.trim_trailing("/")
    |> join_url(Path.join(config.bucket, key))
  end

  defp join_url(base, path) do
    encoded_path =
      path
      |> String.split("/", trim: true)
      |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)

    base
    |> URI.parse()
    |> URI.append_path("/#{encoded_path}")
    |> URI.to_string()
  end

  defp config!(opts) do
    case Keyword.get(opts, :config) || config() do
      {:ok, config} ->
        config

      %__MODULE__{} = config ->
        config

      {:error, reason} ->
        raise ArgumentError, "object storage is not configured: #{inspect(reason)}"
    end
  end

  defp config_from_s3(s3) do
    case s3_config(provider: :s3, s3: s3) do
      {:ok, config} -> {:ok, struct!(__MODULE__, config)}
      {:error, {:missing, missing}} -> {:error, {:missing, missing}}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
