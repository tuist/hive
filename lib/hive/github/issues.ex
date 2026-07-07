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
  repository can be a `Hive.Domains.GitHubRepository` or any struct/map
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

  def list_labels(repository, opts \\ []) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts) do
      fetch_labels(config, token, repository, opts)
    end
  end

  def create_issue(repository, attrs, opts \\ []) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts) do
      create(config, token, repository, attrs, opts)
    end
  end

  @doc """
  Fetches a single issue or pull request by number. GitHub's REST
  `/repos/:owner/:repo/issues/:number` endpoint returns both issues and
  PRs; PRs include a `pull_request` key in the payload.
  """
  def get_issue(repository, issue_number, opts \\ []) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts) do
      fetch_one(config, token, repository, issue_number, opts)
    end
  end

  defp fetch_one(config, token, %{owner: owner, name: name}, number, opts) do
    url = "#{config.api_url}/repos/#{owner}/#{name}/issues/#{number}"

    Client.request(
      [method: :get, url: url, headers: Client.headers(token)],
      opts
    )
    |> case do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, issue_from_api(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create(config, token, %{owner: owner, name: name}, attrs, opts) do
    url = "#{config.api_url}/repos/#{owner}/#{name}/issues"

    Client.request(
      [
        method: :post,
        url: url,
        headers: Client.headers(token),
        json: create_issue_body(attrs)
      ],
      opts
    )
    |> case do
      {:ok, %{status: status, body: body}} when status in [200, 201] and is_map(body) ->
        {:ok, issue_from_api(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch(config, token, %{owner: owner, name: name}, opts) do
    fetch(config, token, owner, name, opts, 1, [])
  end

  defp create_issue_body(attrs) do
    %{}
    |> put_present("title", attr(attrs, :title))
    |> put_present("body", attr(attrs, :body))
    |> put_labels(attr(attrs, :labels))
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, _key, ""), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp put_labels(map, labels) when is_list(labels) do
    labels = labels |> Enum.filter(&is_binary/1) |> Enum.reject(&(&1 == ""))

    if labels == [] do
      map
    else
      Map.put(map, "labels", labels)
    end
  end

  defp put_labels(map, _labels), do: map

  defp attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
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

  defp fetch_labels(config, token, %{owner: owner, name: name}, opts) do
    fetch_labels(config, token, owner, name, opts, 1, [])
  end

  defp fetch_labels(_config, _token, _owner, _name, _opts, page, acc)
       when page > @max_pages do
    {:ok, acc}
  end

  defp fetch_labels(config, token, owner, name, opts, page, acc) do
    url = "#{config.api_url}/repos/#{owner}/#{name}/labels?per_page=#{@per_page}&page=#{page}"

    Client.request(
      [method: :get, url: url, headers: Client.headers(token)],
      opts
    )
    |> case do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        labels =
          body
          |> Enum.map(&label_option_from_api/1)
          |> Enum.reject(&is_nil/1)

        acc = acc ++ labels

        if length(body) == @per_page do
          fetch_labels(config, token, owner, name, opts, page + 1, acc)
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

  defp label_option_from_api(%{"name" => name} = label) when is_binary(name) do
    %{
      name: name,
      color: label["color"],
      description: label["description"]
    }
  end

  defp label_option_from_api(_label), do: nil

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
