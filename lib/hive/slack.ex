defmodule Hive.Slack do
  @moduledoc """
  Slack integration for Hive.

  Hive registers one Slack app per deployment, configured via
  `HIVE_SLACK_CLIENT_ID`, `HIVE_SLACK_CLIENT_SECRET`, and
  `HIVE_SLACK_SIGNING_SECRET`. With Slack's Public Distribution toggle
  enabled on the app, any workspace can install it through the OAuth v2
  flow at `/slack/install` without going through the Slack App Directory.

  Each installed workspace becomes a `Hive.Slack.Installation` row that
  holds the per-workspace bot token; inbound events and interactions
  are routed by `team_id` to the matching installation. When the
  configuration env vars are missing, `enabled?/0` returns `false` and
  the install flow is hidden.
  """

  import Ecto.Query

  alias Hive.Accounts
  alias Hive.Repo
  alias Hive.Slack.Channel
  alias Hive.Slack.Installation
  alias Hive.Slack.Message
  alias Hive.Slack.User, as: SlackUser

  @default_bot_scopes [
    "app_mentions:read",
    "channels:history",
    "channels:read",
    "chat:write",
    "chat:write.public",
    "commands",
    "groups:history",
    "groups:read",
    "im:history",
    "im:read",
    "links:read",
    "links:write",
    "mpim:history",
    "mpim:read",
    "users:read",
    "users:read.email"
  ]

  @doc """
  Default OAuth bot scopes Hive requests at install time.
  """
  def default_bot_scopes, do: @default_bot_scopes

  @doc """
  Returns the configured Slack app credentials as a map, or `nil` when
  any of the three env vars (`HIVE_SLACK_CLIENT_ID`,
  `HIVE_SLACK_CLIENT_SECRET`, `HIVE_SLACK_SIGNING_SECRET`) is missing.

  Shape:
    `%{client_id: binary, client_secret: binary, signing_secret: binary,
       scopes: [binary]}`
  """
  def config(conf \\ Application.get_env(:hive, :slack, [])) do
    with client_id when is_binary(client_id) and client_id != "" <-
           Keyword.get(conf, :client_id),
         client_secret when is_binary(client_secret) and client_secret != "" <-
           Keyword.get(conf, :client_secret),
         signing_secret when is_binary(signing_secret) and signing_secret != "" <-
           Keyword.get(conf, :signing_secret) do
      %{
        client_id: client_id,
        client_secret: client_secret,
        signing_secret: signing_secret,
        scopes: scopes_value(Keyword.get(conf, :scopes))
      }
    else
      _ -> nil
    end
  end

  @doc """
  Returns `true` when Hive can offer Slack workspace installs.
  """
  def enabled?, do: config() != nil

  defp scopes_value(nil), do: @default_bot_scopes
  defp scopes_value(""), do: @default_bot_scopes

  defp scopes_value(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> @default_bot_scopes
      list -> list
    end
  end

  defp scopes_value(value) when is_list(value), do: value

  @doc """
  Lists installations (most recent first), preloading the user that
  initially installed each workspace.
  """
  def list_installations do
    Installation
    |> order_by([installation], desc: installation.inserted_at)
    |> preload(:installed_by_user)
    |> Repo.all()
  end

  def get_installation(nil), do: nil
  def get_installation(id), do: Installation |> preload(:installed_by_user) |> Repo.get(id)

  @doc """
  Fetches an installation by Slack `team_id`. Returns `nil` if no row
  exists or if the row has been disconnected.
  """
  def find_active_installation_by_team_id(team_id) when is_binary(team_id) do
    case Repo.get_by(Installation, team_id: team_id) do
      nil -> nil
      installation -> if Installation.connected?(installation), do: installation, else: nil
    end
  end

  def find_active_installation_by_team_id(_team_id), do: nil

  @doc """
  Upserts a Slack channel by `{installation_id, slack_channel_id}`.
  """
  def upsert_channel(%Installation{id: installation_id}, attrs) when is_map(attrs) do
    slack_channel_id = attrs[:slack_channel_id] || attrs["slack_channel_id"] || attrs["id"]
    attrs = Map.put(attrs, :installation_id, installation_id)

    existing =
      Repo.get_by(Channel,
        installation_id: installation_id,
        slack_channel_id: slack_channel_id
      )

    (existing || %Channel{})
    |> Channel.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Upserts a Slack user by `{installation_id, slack_user_id}`. When
  `:email` is set and matches a Hive user (case-insensitive), the row
  links to it via `linked_user_id`.
  """
  def upsert_user(%Installation{id: installation_id}, attrs) when is_map(attrs) do
    slack_user_id = attrs[:slack_user_id] || attrs["slack_user_id"] || attrs["id"]

    attrs =
      attrs
      |> Map.put(:installation_id, installation_id)
      |> maybe_link_hive_user()

    existing =
      Repo.get_by(SlackUser,
        installation_id: installation_id,
        slack_user_id: slack_user_id
      )

    (existing || %SlackUser{})
    |> SlackUser.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp maybe_link_hive_user(attrs) do
    email = attrs[:email] || attrs["email"]

    if is_binary(email) and email != "" do
      case Accounts.get_user_by_email(email) do
        nil -> attrs
        user -> Map.put(attrs, :linked_user_id, user.id)
      end
    else
      attrs
    end
  end

  @doc """
  Inserts a Slack message under a channel + installation. Returns
  `{:ok, message}` on success and `{:ok, existing}` when a row with the
  same `(channel_id, slack_ts)` already exists.
  """
  def insert_message(%Installation{id: installation_id}, %Channel{id: channel_id}, attrs)
      when is_map(attrs) do
    attrs =
      attrs
      |> Map.put(:installation_id, installation_id)
      |> Map.put(:channel_id, channel_id)

    case Repo.get_by(Message, channel_id: channel_id, slack_ts: attrs[:slack_ts]) do
      nil ->
        %Message{}
        |> Message.changeset(attrs)
        |> Repo.insert()

      message ->
        {:ok, message}
    end
  end
end
