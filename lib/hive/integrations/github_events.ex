defmodule Hive.Integrations.GitHubEvents do
  @moduledoc """
  Handles incoming GitHub webhook events and creates signals from monitored repositories.
  """

  alias Hive.Integrations
  alias Hive.Signals

  require Logger

  def verify_signature(raw_body, signature, webhook_secret) do
    expected =
      "sha256=" <>
        (:crypto.mac(:hmac, :sha256, webhook_secret, raw_body) |> Base.encode16(case: :lower))

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def handle_event("issues", %{"action" => "opened"} = payload) do
    repo = payload["repository"]
    issue = payload["issue"]
    full_name = repo["full_name"]
    [owner, repo_name] = String.split(full_name, "/")

    case Integrations.find_monitored_repository(owner, repo_name) do
      nil ->
        :ignored

      _repository ->
        handle_new_issue(issue, full_name)
    end
  end

  def handle_event("issue_comment", %{"action" => "created"} = payload) do
    repo = payload["repository"]
    issue = payload["issue"]
    comment = payload["comment"]
    full_name = repo["full_name"]
    [owner, repo_name] = String.split(full_name, "/")

    case Integrations.find_monitored_repository(owner, repo_name) do
      nil ->
        :ignored

      _repository ->
        handle_issue_comment(comment, issue, full_name)
    end
  end

  def handle_event(_event_type, _payload), do: :ignored

  defp handle_new_issue(issue, full_name) do
    attrs = %{
      title: issue["title"],
      body: issue["body"],
      source: "github",
      source_author: issue["user"]["login"],
      source_channel: full_name,
      source_url: issue["html_url"],
      source_timestamp: parse_timestamp(issue["created_at"])
    }

    case Signals.create_signal(attrs) do
      {:ok, signal} ->
        Logger.info("Created signal from GitHub issue ##{issue["number"]} in #{full_name}")
        {:ok, signal}

      {:error, changeset} ->
        Logger.error("Failed to create signal: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp handle_issue_comment(comment, issue, full_name) do
    source_url = issue["html_url"]

    case Signals.get_signal_by_source_url(source_url) do
      nil ->
        Logger.debug("No signal found for issue #{issue["html_url"]}")
        :ignored

      signal ->
        attrs = %{
          author: comment["user"]["login"],
          body: comment["body"],
          source_url: comment["html_url"],
          source_timestamp: parse_timestamp(comment["created_at"])
        }

        case Signals.add_signal_message(signal, attrs) do
          {:ok, message} ->
            Logger.info("Added comment to signal #{signal.id} from #{full_name}")
            {:ok, message}

          {:error, changeset} ->
            Logger.error("Failed to add signal message: #{inspect(changeset.errors)}")
            {:error, changeset}
        end
    end
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()
end
