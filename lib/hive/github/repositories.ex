defmodule Hive.GitHub.Repositories do
  @moduledoc """
  Searches repositories visible to the configured GitHub App installation.
  """

  @api_version "2022-11-28"
  @per_page 100

  defmodule Config do
    @moduledoc false

    defstruct [:app_id, :installation_id, :private_key, :api_url]
  end

  defstruct [:owner, :name, :description]

  def search_accessible_repositories(query, opts \\ []) do
    query = normalize_query(query)

    with {:ok, config} <- config(opts),
         {:ok, token} <- installation_token(config, opts),
         {:ok, repositories} <- list_installation_repositories(config, token, opts) do
      {:ok,
       repositories
       |> Enum.filter(&matches?(&1, query))
       |> Enum.take(20)}
    end
  end

  def full_name(%__MODULE__{} = repository), do: "#{repository.owner}/#{repository.name}"

  def configured? do
    match?({:ok, _config}, config())
  end

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

  defp installation_token(config, opts) do
    case Keyword.get(opts, :installation_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _other -> create_installation_token(config, opts)
    end
  end

  defp create_installation_token(config, opts) do
    request = Keyword.get(opts, :request, &Req.request/1)

    with {:ok, jwt} <- app_jwt(config) do
      request.(
        method: :post,
        url: "#{config.api_url}/app/installations/#{config.installation_id}/access_tokens",
        headers: github_headers(jwt)
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

  defp list_installation_repositories(config, token, opts) do
    request = Keyword.get(opts, :request, &Req.request/1)
    list_installation_repositories(config, token, request, 1, [])
  end

  defp list_installation_repositories(config, token, request, page, acc) do
    request.(
      method: :get,
      url: "#{config.api_url}/installation/repositories?per_page=#{@per_page}&page=#{page}",
      headers: github_headers(token)
    )
    |> case do
      {:ok, %{status: 200, body: %{"repositories" => repositories}}} ->
        parsed = Enum.map(repositories, &repository_from_api/1)
        acc = acc ++ parsed

        if length(repositories) == @per_page do
          list_installation_repositories(config, token, request, page + 1, acc)
        else
          {:ok, acc}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp repository_from_api(%{"full_name" => full_name} = repository) do
    {owner, name} =
      case String.split(full_name, "/", parts: 2) do
        [owner, name] -> {owner, name}
        _other -> {get_in(repository, ["owner", "login"]), repository["name"]}
      end

    %__MODULE__{
      owner: owner,
      name: name,
      description: repository["description"]
    }
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

  defp github_headers(token) do
    [
      {"accept", "application/vnd.github+json"},
      {"authorization", "Bearer #{token}"},
      {"x-github-api-version", @api_version},
      {"user-agent", "hive"}
    ]
  end

  defp matches?(_repository, ""), do: true

  defp matches?(repository, query) do
    repository
    |> full_name()
    |> String.downcase()
    |> String.contains?(query)
  end

  defp normalize_query(query) when is_binary(query) do
    query
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_query(_query), do: ""

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
