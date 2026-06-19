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
  alias Hive.Accounts.User
  alias Hive.Audit
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
  @notification_events ["spec.created", "spec.comment.created"]
  @profile_scopes ["openid", "profile", "email"]

  @doc """
  Default OAuth bot scopes Hive requests at install time.
  """
  def default_bot_scopes, do: @default_bot_scopes

  def profile_scopes, do: @profile_scopes

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

  @doc """
  Returns the product activity events Slack notifications support.
  """
  def notification_events, do: @notification_events

  def default_notification_events, do: @notification_events

  def notification_event_label("spec.created"), do: "New specs"
  def notification_event_label("spec.comment.created"), do: "New spec comments"
  def notification_event_label(event), do: event

  def notification_targets_for(event) when is_binary(event) do
    Installation
    |> where([installation], is_nil(installation.disconnected_at))
    |> where([installation], not is_nil(installation.bot_token) and installation.bot_token != "")
    |> where(
      [installation],
      not is_nil(installation.notification_channel_id) and
        installation.notification_channel_id != ""
    )
    |> Repo.all()
    |> Enum.filter(&(event in notification_events_for(&1)))
  end

  def notification_enabled_for?(event) when is_binary(event),
    do: notification_targets_for(event) != []

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

  def notification_events_for(%Installation{notification_events: events})
      when is_list(events) and events != [],
      do: events

  def notification_events_for(%Installation{}), do: default_notification_events()

  def change_notification_settings(%Installation{} = installation, attrs \\ %{}) do
    Installation.notification_changeset(installation, attrs, notification_events())
  end

  def update_notification_settings(%Installation{} = installation, attrs) do
    installation
    |> change_notification_settings(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        Audit.record("slack.notification_settings.updated", %{
          target_type: "slack_installation",
          target_id: updated.id,
          target_label: updated.team_name || updated.team_id,
          metadata: %{
            team_id: updated.team_id,
            notification_channel_id: updated.notification_channel_id,
            notification_events: updated.notification_events
          }
        })

        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

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

  def get_linked_user_profile(%User{id: user_id}, installation_id)
      when is_binary(installation_id) do
    SlackUser
    |> where([slack_user], slack_user.installation_id == ^installation_id)
    |> where([slack_user], slack_user.linked_user_id == ^user_id)
    |> preload(:installation)
    |> Repo.one()
  end

  def get_linked_user_profile(_user, _installation_id), do: nil

  def list_linked_user_profiles(%User{id: user_id}) do
    SlackUser
    |> where([slack_user], slack_user.linked_user_id == ^user_id)
    |> preload(:installation)
    |> order_by([slack_user], asc: slack_user.inserted_at)
    |> Repo.all()
  end

  def list_linked_user_profiles(_user), do: []

  def profile_authorize_url(redirect_uri, state, conf \\ config()) do
    case conf do
      nil ->
        {:error, :not_configured}

      %{client_id: client_id} ->
        query =
          URI.encode_query(%{
            "client_id" => client_id,
            "scope" => Enum.join(profile_scopes(), " "),
            "redirect_uri" => redirect_uri,
            "response_type" => "code",
            "state" => state
          })

        {:ok, "https://slack.com/openid/connect/authorize?" <> query}
    end
  end

  def complete_profile_link(code, redirect_uri, %User{} = user, opts \\ [])
      when is_binary(code) do
    conf = Keyword.get(opts, :config) || config()

    case conf do
      nil ->
        {:error, :not_configured}

      %{client_id: client_id, client_secret: client_secret} ->
        with {:ok, token} <- request_profile_token(code, redirect_uri, client_id, client_secret),
             {:ok, profile} <- request_profile_info(token),
             {:ok, attrs} <- profile_attrs(profile),
             %Installation{} = installation <-
               find_active_installation_by_team_id(attrs.installation_team_id) ||
                 {:error, :workspace_not_installed} do
          link_user_profile(installation, attrs, user)
        end
    end
  end

  defp request_profile_token(code, redirect_uri, client_id, client_secret) do
    body =
      URI.encode_query(%{
        "code" => code,
        "redirect_uri" => redirect_uri,
        "grant_type" => "authorization_code"
      })

    case Req.post("https://slack.com/api/openid.connect.token",
           headers: [{"content-type", "application/x-www-form-urlencoded"}],
           auth: {:basic, client_id <> ":" <> client_secret},
           body: body
         ) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "access_token" => token}}}
      when is_binary(token) and token != "" ->
        {:ok, token}

      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, {:slack_openid_error, error}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:slack_openid_http, status}}

      {:error, reason} ->
        {:error, {:slack_openid_transport, reason}}
    end
  end

  defp request_profile_info(token) do
    case Req.get("https://slack.com/api/openid.connect.userInfo",
           headers: [{"authorization", "Bearer " <> token}]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true} = body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => error}}} ->
        {:error, {:slack_openid_error, error}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:slack_openid_http, status}}

      {:error, reason} ->
        {:error, {:slack_openid_transport, reason}}
    end
  end

  defp profile_attrs(profile) do
    slack_user_id = profile["https://slack.com/user_id"] || profile["sub"]
    team_id = profile["https://slack.com/team_id"]

    if is_binary(slack_user_id) and slack_user_id != "" and is_binary(team_id) and team_id != "" do
      {:ok,
       %{
         installation_team_id: team_id,
         slack_user_id: slack_user_id,
         email: profile["email"],
         name: profile["name"],
         real_name: profile["name"],
         deleted: false,
         is_bot: false
       }}
    else
      {:error, :slack_openid_missing_identity}
    end
  end

  defp link_user_profile(%Installation{} = installation, attrs, %User{} = user) do
    attrs =
      attrs
      |> Map.drop([:installation_team_id])
      |> Map.put(:linked_user_id, user.id)

    Repo.transaction(fn ->
      from(slack_user in SlackUser,
        where:
          slack_user.installation_id == ^installation.id and
            slack_user.linked_user_id == ^user.id and
            slack_user.slack_user_id != ^attrs.slack_user_id
      )
      |> Repo.update_all(set: [linked_user_id: nil])

      case upsert_user(installation, attrs) do
        {:ok, slack_user} -> slack_user
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, slack_user} ->
        Audit.record("slack.profile.linked", %{
          actor: user,
          target_type: "slack_user",
          target_id: slack_user.id,
          target_label: installation.team_name || installation.team_id,
          metadata: %{
            team_id: installation.team_id,
            slack_user_id: slack_user.slack_user_id
          }
        })

        {:ok, slack_user}

      {:error, reason} ->
        {:error, reason}
    end
  end

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
    linked_user_id = attrs[:linked_user_id] || attrs["linked_user_id"]

    cond do
      is_binary(linked_user_id) and linked_user_id != "" ->
        attrs

      is_binary(email) and email != "" ->
        case Accounts.get_user_by_email(email) do
          nil -> attrs
          user -> Map.put(attrs, :linked_user_id, user.id)
        end

      true ->
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
