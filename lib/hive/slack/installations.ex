defmodule Hive.Slack.Installations do
  @moduledoc """
  Completes Slack OAuth installs and persists one row per workspace.
  """

  alias Hive.Audit
  alias Hive.Repo
  alias Hive.Slack
  alias Hive.Slack.Installation

  @oauth_url "https://slack.com/api/oauth.v2.access"

  @doc """
  Builds the Slack authorize URL the operator/user is redirected to at
  install time. The caller passes a signed `state` token so it can
  verify the callback.
  """
  def authorize_url(redirect_uri, state, conf \\ Slack.config()) do
    case conf do
      nil ->
        {:error, :not_configured}

      %{client_id: client_id, scopes: scopes} ->
        query =
          URI.encode_query(%{
            "client_id" => client_id,
            "scope" => Enum.join(scopes, ","),
            "redirect_uri" => redirect_uri,
            "state" => state
          })

        {:ok, "https://slack.com/oauth/v2/authorize?" <> query}
    end
  end

  @doc """
  Exchanges an OAuth `code` for a bot token and upserts the installation
  row keyed by `team_id`. The `installed_by_user_id` is optional and
  reflects which Hive user initiated the install.
  """
  def complete_install(code, redirect_uri, opts \\ [])

  def complete_install(code, redirect_uri, opts) when is_binary(code) do
    conf = Keyword.get(opts, :config) || Slack.config()
    installed_by_user_id = Keyword.get(opts, :installed_by_user_id)

    case conf do
      nil ->
        {:error, :not_configured}

      %{client_id: client_id, client_secret: client_secret} ->
        with {:ok, response} <- request_token(code, redirect_uri, client_id, client_secret),
             {:ok, attrs} <- parse_response(response, installed_by_user_id) do
          upsert(attrs)
        end
    end
  end

  defp request_token(code, redirect_uri, client_id, client_secret) do
    headers = [
      {"content-type", "application/x-www-form-urlencoded"}
    ]

    body =
      URI.encode_query(%{
        "code" => code,
        "redirect_uri" => redirect_uri
      })

    case Req.post(@oauth_url,
           headers: headers,
           auth: {:basic, client_id <> ":" <> client_secret},
           body: body
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:slack_oauth_http, status}}

      {:error, reason} ->
        {:error, {:slack_oauth_transport, reason}}
    end
  end

  defp parse_response(%{"ok" => true} = body, installed_by_user_id) do
    team = body["team"] || %{}
    bot_token = body["access_token"]

    if is_binary(bot_token) and bot_token != "" do
      {:ok,
       %{
         team_id: team["id"],
         team_name: team["name"],
         bot_user_id: body["bot_user_id"],
         bot_token: bot_token,
         scope: body["scope"],
         installed_at: DateTime.utc_now() |> DateTime.truncate(:second),
         disconnected_at: nil,
         installed_by_user_id: installed_by_user_id
       }}
    else
      {:error, :missing_access_token}
    end
  end

  defp parse_response(%{"ok" => false, "error" => error}, _),
    do: {:error, {:slack_oauth_error, error}}

  defp parse_response(_body, _), do: {:error, :slack_oauth_invalid_response}

  defp upsert(%{team_id: team_id} = attrs) when is_binary(team_id) and team_id != "" do
    existing = Repo.get_by(Installation, team_id: team_id)

    (existing || %Installation{})
    |> Installation.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, installation} ->
        Audit.record("slack.installation.connected", %{
          target_type: "slack_installation",
          target_id: installation.id,
          target_label: installation.team_name || installation.team_id,
          metadata: %{team_id: installation.team_id, team_name: installation.team_name}
        })

        {:ok, installation}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp upsert(_attrs), do: {:error, :missing_team_id}

  @doc """
  Disconnects an installation (nulls the bot token + sets
  `disconnected_at`) without deleting the row, so the audit history of
  the workspace install/disconnect stays intact.
  """
  def disconnect(%Installation{} = installation) do
    case installation |> Installation.disconnect_changeset() |> Repo.update() do
      {:ok, updated} ->
        Audit.record("slack.installation.disconnected", %{
          target_type: "slack_installation",
          target_id: updated.id,
          target_label: updated.team_name || updated.team_id,
          metadata: %{team_id: updated.team_id}
        })

        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end
