defmodule Hive.GitHub.Issues do
  @moduledoc """
  Fetches open issues from a GitHub repository using the installation
  token of the configured GitHub App. Pull requests are filtered out — the
  REST `/issues` endpoint returns them alongside real issues otherwise.
  """

  alias Hive.GitHub.Client

  @per_page 100
  @max_pages 5

  defmodule Comment do
    @moduledoc false

    defstruct [
      :id,
      :body,
      :html_url,
      :user_login,
      :user_avatar_url,
      :created_at,
      :updated_at
    ]
  end

  defstruct [
    :number,
    :title,
    :body,
    :state,
    :html_url,
    :user_login,
    :user_avatar_url,
    :labels,
    :comments,
    :created_at,
    :updated_at
  ]

  @doc """
  Lists open issues for a repository identified by `owner` and `name`. The
  repository can be a `Hive.Meadows.GitHubRepository` or any struct/map
  exposing `:owner` and `:name` keys.
  """
  def list_open_issues(repository, opts \\ []) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts) do
      fetch(config, token, repository, opts)
    end
  end

  def list_comments(repository, issue_number, opts \\ []) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts) do
      fetch_comments(config, token, repository, issue_number, opts)
    end
  end

  defp fetch(config, token, %{owner: owner, name: name}, opts) do
    fetch(config, token, owner, name, opts, 1, [])
  end

  defp fetch(_config, _token, _owner, _name, _opts, page, acc) when page > @max_pages do
    {:ok, acc}
  end

  defp fetch(config, token, owner, name, opts, page, acc) do
    url =
      "#{config.api_url}/repos/#{owner}/#{name}/issues" <>
        "?state=open&per_page=#{@per_page}&page=#{page}&sort=updated&direction=desc"

    Client.request(
      [method: :get, url: url, headers: Client.headers(token)],
      opts
    )
    |> case do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        parsed =
          body
          |> Enum.reject(&pull_request?/1)
          |> Enum.map(&issue_from_api/1)

        acc = acc ++ parsed

        if length(body) == @per_page do
          fetch(config, token, owner, name, opts, page + 1, acc)
        else
          {:ok, acc}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_comments(config, token, %{owner: owner, name: name}, issue_number, opts) do
    fetch_comments(config, token, owner, name, issue_number, opts, 1, [])
  end

  defp fetch_comments(_config, _token, _owner, _name, _issue_number, _opts, page, acc)
       when page > @max_pages do
    {:ok, acc}
  end

  defp fetch_comments(config, token, owner, name, issue_number, opts, page, acc) do
    url =
      "#{config.api_url}/repos/#{owner}/#{name}/issues/#{issue_number}/comments" <>
        "?per_page=#{@per_page}&page=#{page}"

    Client.request(
      [method: :get, url: url, headers: Client.headers(token)],
      opts
    )
    |> case do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        comments = Enum.map(body, &comment_from_api/1)
        acc = acc ++ comments

        if length(body) == @per_page do
          fetch_comments(config, token, owner, name, issue_number, opts, page + 1, acc)
        else
          {:ok, acc}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pull_request?(%{"pull_request" => pull_request}) when not is_nil(pull_request), do: true
  defp pull_request?(_issue), do: false

  defp issue_from_api(issue) do
    %__MODULE__{
      number: issue["number"],
      title: issue["title"],
      body: issue["body"],
      state: issue["state"],
      html_url: issue["html_url"],
      user_login: get_in(issue, ["user", "login"]),
      user_avatar_url: get_in(issue, ["user", "avatar_url"]),
      labels: Enum.map(issue["labels"] || [], &label_from_api/1),
      comments: issue["comments"] || 0,
      created_at: issue["created_at"],
      updated_at: issue["updated_at"]
    }
  end

  defp label_from_api(%{"name" => name, "color" => color}), do: %{name: name, color: color}
  defp label_from_api(%{"name" => name}), do: %{name: name, color: nil}
  defp label_from_api(_label), do: nil

  defp comment_from_api(comment) do
    %Comment{
      id: comment["id"],
      body: comment["body"],
      html_url: comment["html_url"],
      user_login: get_in(comment, ["user", "login"]),
      user_avatar_url: get_in(comment, ["user", "avatar_url"]),
      created_at: comment["created_at"],
      updated_at: comment["updated_at"]
    }
  end
end
