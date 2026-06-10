defmodule Hive.GitHub.Client do
  @moduledoc """
  Shared GitHub App authentication and request plumbing. Resolves the
  installation token from the app's private key and exposes a `request/2`
  helper for the rest of `Hive.GitHub.*` to make authenticated calls.
  """

  @api_version "2022-11-28"

  defmodule Config do
    @moduledoc false

    defstruct [:app_id, :installation_id, :private_key, :api_url]
  end

  def api_version, do: @api_version

  def config(opts \\ []) do
    opts
    |> Keyword.get(:config)
    |> case do
      %Config{} = config ->
        validate_config(config)

      nil ->
        :hive
        |> Application.get_env(:github_app, [])
        |> config_from_application_env()
        |> validate_config()
    end
  end

  def configured?, do: match?({:ok, _config}, config())

  def installation_token(config, opts \\ []) do
    case Keyword.get(opts, :installation_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _other -> create_installation_token(config, opts)
    end
  end

  def request(opts, request_opts) when is_list(opts) do
    request = Keyword.get(request_opts, :request, &Req.request/1)
    request.(opts)
  end

  def headers(token) do
    [
      {"accept", "application/vnd.github+json"},
      {"authorization", "Bearer #{token}"},
      {"x-github-api-version", @api_version},
      {"user-agent", "hive"}
    ]
  end

  defp create_installation_token(config, opts) do
    with {:ok, jwt} <- app_jwt(config) do
      request(
        [
          method: :post,
          url: "#{config.api_url}/app/installations/#{config.installation_id}/access_tokens",
          headers: headers(jwt)
        ],
        opts
      )
      |> case do
        {:ok, %{status: 201, body: %{"token" => token}}} ->
          {:ok, token}

        {:ok, %{status: status, body: body}} ->
          {:error, {:unexpected_status, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp app_jwt(%Config{} = config) do
    with {:ok, private_key} <- private_key(config.private_key) do
      now = System.system_time(:second)
      jwk = JOSE.JWK.from_pem(private_key)

      jwt = %{
        "iat" => now - 60,
        "exp" => now + 540,
        "iss" => to_string(config.app_id)
      }

      {_format, token} =
        jwk
        |> JOSE.JWT.sign(%{"alg" => "RS256"}, jwt)
        |> JOSE.JWS.compact()

      {:ok, token}
    end
  rescue
    _error -> {:error, :invalid_private_key}
  end

  defp private_key(value) when is_binary(value) do
    value = String.trim(value)

    if String.contains?(value, "BEGIN") do
      {:ok, String.replace(value, "\\n", "\n")}
    else
      Base.decode64(value)
    end
  end

  defp private_key(_value), do: {:error, :invalid_private_key}

  defp config_from_application_env(env) do
    %Config{
      app_id: Keyword.get(env, :app_id),
      installation_id: Keyword.get(env, :installation_id),
      private_key: Keyword.get(env, :private_key),
      api_url: Keyword.get(env, :api_url, "https://api.github.com")
    }
  end

  defp validate_config(%Config{} = config) do
    missing =
      [:app_id, :installation_id, :private_key]
      |> Enum.reject(&present?(Map.get(config, &1)))

    if missing == [] do
      {:ok, %{config | api_url: normalize_api_url(config.api_url)}}
    else
      {:error, {:not_configured, missing}}
    end
  end

  defp normalize_api_url(nil), do: "https://api.github.com"

  defp normalize_api_url(api_url) when is_binary(api_url) do
    api_url
    |> String.trim()
    |> String.trim_trailing("/")
    |> case do
      "" -> "https://api.github.com"
      value -> value
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
