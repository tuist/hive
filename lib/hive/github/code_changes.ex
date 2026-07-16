defmodule Hive.GitHub.CodeChanges do
  @moduledoc """
  Downloads an exact repository snapshot and publishes changed files through
  the GitHub Git Data application programming interface.

  The sandbox never receives the GitHub installation token. Hive downloads
  the source before execution and turns the returned file set into a commit,
  branch, and pull request after execution.
  """

  alias Hive.Domains.GitHubRepository
  alias Hive.GitHub.Client

  @doc """
  Fetches the repository's default branch, current commit and tree identifiers,
  and a compressed source archive.
  """
  def fetch_source(%GitHubRepository{} = repository, opts \\ []) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts),
         {:ok, metadata} <- get(config, token, repository_path(repository), opts),
         {:ok, branch} <- required_string(metadata, "default_branch"),
         {:ok, ref} <-
           get(config, token, "#{repository_path(repository)}/git/ref/heads/#{branch}", opts),
         {:ok, sha} <- required_string(get_in(ref, ["object"]), "sha"),
         {:ok, commit} <-
           get(config, token, "#{repository_path(repository)}/git/commits/#{sha}", opts),
         {:ok, tree_sha} <- required_string(commit["tree"], "sha"),
         {:ok, archive} <- archive(config, token, repository, sha, opts) do
      {:ok,
       %{
         archive: archive,
         base_branch: branch,
         base_sha: sha,
         base_tree_sha: tree_sha
       }}
    end
  end

  @doc """
  Creates blobs for the supplied changed files, commits them on a new branch,
  and opens a pull request.
  """
  def publish(%GitHubRepository{} = repository, source, changes, attrs, opts \\ [])
      when is_list(changes) and is_map(attrs) do
    with {:ok, config} <- Client.config(opts),
         {:ok, token} <- Client.installation_token(config, opts),
         {:ok, entries} <- create_tree_entries(config, token, repository, changes, opts),
         {:ok, tree} <-
           post(
             config,
             token,
             "#{repository_path(repository)}/git/trees",
             %{
               "base_tree" => source.base_tree_sha,
               "tree" => entries
             },
             opts
           ),
         {:ok, tree_sha} <- required_string(tree, "sha"),
         {:ok, commit} <-
           post(
             config,
             token,
             "#{repository_path(repository)}/git/commits",
             %{
               "message" => Map.fetch!(attrs, :commit_message),
               "parents" => [source.base_sha],
               "tree" => tree_sha
             },
             opts
           ),
         {:ok, commit_sha} <- required_string(commit, "sha"),
         :ok <-
           create_branch(config, token, repository, Map.fetch!(attrs, :branch), commit_sha, opts),
         {:ok, pull_request} <-
           post(
             config,
             token,
             "#{repository_path(repository)}/pulls",
             %{
               "base" => source.base_branch,
               "body" => Map.fetch!(attrs, :body),
               "head" => Map.fetch!(attrs, :branch),
               "title" => Map.fetch!(attrs, :title)
             },
             opts
           ) do
      {:ok,
       %{
         number: pull_request["number"],
         title: pull_request["title"] || Map.fetch!(attrs, :title),
         url: pull_request["html_url"]
       }}
    end
  end

  defp create_tree_entries(config, token, repository, changes, opts) do
    Enum.reduce_while(changes, {:ok, []}, fn change, {:ok, entries} ->
      case tree_entry(config, token, repository, change, opts) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp tree_entry(_config, _token, _repository, %{path: path, deleted?: true}, _opts) do
    {:ok, %{"path" => path, "mode" => "100644", "type" => "blob", "sha" => nil}}
  end

  defp tree_entry(config, token, repository, change, opts) do
    with {:ok, blob} <-
           post(
             config,
             token,
             "#{repository_path(repository)}/git/blobs",
             %{
               "content" => Base.encode64(change.content),
               "encoding" => "base64"
             },
             opts
           ),
         {:ok, sha} <- required_string(blob, "sha") do
      {:ok,
       %{
         "path" => change.path,
         "mode" => change.mode,
         "type" => "blob",
         "sha" => sha
       }}
    end
  end

  defp create_branch(config, token, repository, branch, sha, opts) do
    case post(
           config,
           token,
           "#{repository_path(repository)}/git/refs",
           %{
             "ref" => "refs/heads/#{branch}",
             "sha" => sha
           },
           opts
         ) do
      {:ok, _ref} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp archive(config, token, repository, sha, opts) do
    request_opts = [
      method: :get,
      url: "#{config.api_url}#{repository_path(repository)}/tarball/#{sha}",
      headers: Client.headers(token),
      redirect: true,
      decode_body: false
    ]

    case Client.request(request_opts, opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {:unexpected_status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get(config, token, path, opts) do
    request(config, token, :get, path, nil, opts)
  end

  defp post(config, token, path, body, opts) do
    request(config, token, :post, path, body, opts)
  end

  defp request(config, token, method, path, body, opts) do
    request_opts = [
      method: method,
      url: "#{config.api_url}#{path}",
      headers: Client.headers(token)
    ]

    request_opts = if body, do: Keyword.put(request_opts, :json, body), else: request_opts

    case Client.request(request_opts, opts) do
      {:ok, %{status: status, body: response_body}}
      when status in 200..201 and is_map(response_body) ->
        {:ok, response_body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {:unexpected_status, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp required_string(map, key) when is_map(map) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_github_field, key}}
    end
  end

  defp required_string(_value, key), do: {:error, {:missing_github_field, key}}

  defp repository_path(repository), do: "/repos/#{repository.owner}/#{repository.name}"
end
