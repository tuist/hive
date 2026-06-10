defmodule Hive.GitHub.Repositories do
  @moduledoc """
  Searches repositories visible to the configured GitHub App installation.
  """

  alias Hive.GitHub.Client

  @per_page 100

  defstruct [:owner, :name, :description, :visibility]

  defdelegate config(opts \\ []), to: Client
  defdelegate configured?, to: Client

  def search_accessible_repositories(query, opts \\ []) do
    query = normalize_query(query)

    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts),
         {:ok, repositories} <- list_installation_repositories(config, token, opts) do
      {:ok,
       repositories
       |> Enum.filter(&matches?(&1, query))
       |> Enum.take(20)}
    end
  end

  def full_name(%__MODULE__{} = repository), do: "#{repository.owner}/#{repository.name}"

  defp list_installation_repositories(config, token, opts) do
    list_installation_repositories(config, token, opts, 1, [])
  end

  defp list_installation_repositories(config, token, opts, page, acc) do
    Client.request(
      [
        method: :get,
        url: "#{config.api_url}/installation/repositories?per_page=#{@per_page}&page=#{page}",
        headers: Client.headers(token)
      ],
      opts
    )
    |> case do
      {:ok, %{status: 200, body: %{"repositories" => repositories}}} ->
        parsed = Enum.map(repositories, &repository_from_api/1)
        acc = acc ++ parsed

        if length(repositories) == @per_page do
          list_installation_repositories(config, token, opts, page + 1, acc)
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
      description: repository["description"],
      visibility: visibility_from_api(repository["private"])
    }
  end

  defp visibility_from_api(true), do: :private
  defp visibility_from_api(_other), do: :public

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
end
