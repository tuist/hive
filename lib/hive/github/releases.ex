defmodule Hive.GitHub.Releases do
  @moduledoc """
  Fetches releases from a GitHub repository using the configured GitHub
  App installation token. Drafts are filtered out — only published
  releases (including pre-releases) are returned.
  """

  alias Hive.GitHub.Client

  @per_page 100
  @max_pages 3

  defstruct [
    :tag_name,
    :name,
    :body,
    :html_url,
    :published_at,
    :created_at,
    :prerelease
  ]

  @doc """
  Lists published releases for a repository identified by `owner` and
  `name`. Accepts a `Hive.Domains.GitHubRepository` or any map exposing
  `:owner` and `:name` keys.
  """
  def list_releases(repository, opts \\ []) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts) do
      fetch(config, token, repository, opts, 1, [])
    end
  end

  defp fetch(_config, _token, _repository, _opts, page, acc) when page > @max_pages do
    {:ok, acc}
  end

  defp fetch(config, token, %{owner: owner, name: name} = repository, opts, page, acc) do
    url =
      "#{config.api_url}/repos/#{owner}/#{name}/releases?per_page=#{@per_page}&page=#{page}"

    Client.request(
      [method: :get, url: url, headers: Client.headers(token)],
      opts
    )
    |> case do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        parsed =
          body
          |> Enum.reject(&draft?/1)
          |> Enum.map(&release_from_api/1)

        acc = acc ++ parsed

        if length(body) == @per_page do
          fetch(config, token, repository, opts, page + 1, acc)
        else
          {:ok, acc}
        end

      {:ok, %{status: 404}} ->
        {:ok, acc}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp draft?(%{"draft" => true}), do: true
  defp draft?(_release), do: false

  defp release_from_api(release) do
    %__MODULE__{
      tag_name: release["tag_name"],
      name: release["name"],
      body: release["body"],
      html_url: release["html_url"],
      published_at: release["published_at"],
      created_at: release["created_at"],
      prerelease: release["prerelease"] == true
    }
  end
end
