defmodule Hive.GitHub.Webhooks do
  @moduledoc """
  Verifies GitHub webhook signatures and handles subscribed events.
  """

  import Ecto.Query

  alias Hive.Audit
  alias Hive.Domains.GitHubRepository
  alias Hive.Errors
  alias Hive.Repo

  @signature_algorithm "sha256"
  @signature_length 64
  @maximum_issue_links 20
  @url_regex ~r|https?://[^\s<>()\[\]{}"'`]+|i
  @issue_path_regex ~r|\A/errors/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/?\z|i

  def secret do
    :hive
    |> Application.get_env(:github_app, [])
    |> Keyword.get(:webhook_secret)
    |> case do
      secret when is_binary(secret) ->
        secret = String.trim(secret)

        if secret == "" do
          {:error, :not_configured}
        else
          {:ok, secret}
        end

      _other ->
        {:error, :not_configured}
    end
  end

  def verify_signature(raw_body, signature, secret)
      when is_binary(raw_body) and is_binary(secret) do
    with {:ok, digest} <- parse_signature(signature),
         expected <- signature(raw_body, secret),
         true <- secure_compare(expected, digest) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      false -> {:error, :invalid_signature}
    end
  end

  def verify_signature(_raw_body, _signature, _secret), do: {:error, :invalid_signature}

  @doc """
  Handles an authenticated GitHub webhook event.

  When a merged pull request belongs to a repository linked to a Hive project,
  error links in its description resolve matching issues from that same project.
  Other events and unlinked repositories are accepted without side effects.
  """
  def handle_event(
        "pull_request",
        %{
          "action" => "closed",
          "pull_request" => %{"merged" => true} = pull_request,
          "repository" => repository
        }
      ) do
    with {:ok, project_id} <- linked_project_id(repository),
         issue_ids <- issue_ids(pull_request["body"]),
         {:ok, resolved_issues} <- Errors.resolve_issues(project_id, issue_ids) do
      record_resolutions(resolved_issues, pull_request, repository)
      :ok
    else
      {:error, :unlinked_repository} -> :ok
      {:error, _reason} = error -> error
    end
  end

  def handle_event(_event, _payload), do: :ok

  defp parse_signature(nil), do: {:error, :missing_signature}

  defp parse_signature(signature) when is_binary(signature) do
    case String.split(String.trim(signature), "=", parts: 2) do
      [algorithm, digest] when algorithm == @signature_algorithm ->
        digest = String.downcase(digest)

        if valid_digest?(digest) do
          {:ok, digest}
        else
          {:error, :invalid_signature}
        end

      _other ->
        {:error, :missing_signature}
    end
  end

  defp parse_signature(_signature), do: {:error, :missing_signature}

  defp signature(raw_body, secret) do
    :hmac
    |> :crypto.mac(:sha256, secret, raw_body)
    |> Base.encode16(case: :lower)
  end

  defp valid_digest?(digest) do
    byte_size(digest) == @signature_length and String.match?(digest, ~r/\A[0-9a-f]+\z/)
  end

  defp secure_compare(left, right) do
    byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)
  end

  defp linked_project_id(repository) do
    with {:ok, owner, name} <- repository_name(repository),
         project_id when is_binary(project_id) <-
           Repo.one(
             from repository in GitHubRepository,
               where: repository.owner == ^owner and repository.name == ^name,
               select: repository.project_id
           ) do
      {:ok, project_id}
    else
      _other -> {:error, :unlinked_repository}
    end
  end

  defp repository_name(%{"full_name" => full_name}) when is_binary(full_name) do
    case String.split(full_name, "/", parts: 2) do
      [owner, name] -> {:ok, String.downcase(owner), String.downcase(name)}
      _other -> {:error, :invalid_repository}
    end
  end

  defp repository_name(%{
         "owner" => %{"login" => owner},
         "name" => name
       })
       when is_binary(owner) and is_binary(name),
       do: {:ok, String.downcase(owner), String.downcase(name)}

  defp repository_name(_repository), do: {:error, :invalid_repository}

  defp issue_ids(body) when is_binary(body) do
    app_host = URI.parse(HiveWeb.Endpoint.url()).host

    @url_regex
    |> Regex.scan(body, capture: :first)
    |> Enum.map(&List.first/1)
    |> Enum.flat_map(&issue_id(&1, app_host))
    |> Enum.uniq()
    |> Enum.take(@maximum_issue_links)
  end

  defp issue_ids(_body), do: []

  defp issue_id(url, app_host) when is_binary(app_host) do
    with %URI{scheme: scheme, host: host, path: path} <- URI.parse(url),
         true <- scheme in ["http", "https"],
         true <- is_binary(host) and String.downcase(host) == String.downcase(app_host),
         [_, issue_id] <- Regex.run(@issue_path_regex, path || "") do
      [String.downcase(issue_id)]
    else
      _other -> []
    end
  end

  defp issue_id(_url, _app_host), do: []

  defp record_resolutions(issues, pull_request, repository) do
    Audit.with_context(
      %{interface: "webhook", actor_kind: "system", actor_name: "GitHub"},
      fn ->
        Enum.each(issues, fn issue ->
          Audit.record("error.resolved", %{
            target_type: "error_issue",
            target_id: issue.id,
            target_label: issue.title,
            metadata: %{
              "pull_request_number" => pull_request["number"],
              "pull_request_url" => pull_request["html_url"],
              "repository" => repository["full_name"]
            }
          })
        end)
      end
    )
  end
end
