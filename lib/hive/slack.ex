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

  use Gettext, backend: HiveWeb.Gettext

  import Ecto.Query

  alias Hive.Accounts
  alias Hive.Accounts.User
  alias Hive.Audit
  alias Hive.Repo
  alias Hive.Slack.API
  alias Hive.Slack.Channel
  alias Hive.Slack.Installation
  alias Hive.Slack.Message
  alias Hive.Slack.NotificationRoute
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
  @spec_notification_events ["spec.created", "spec.comment.created", "spec.review.requested"]
  @notification_route_specs [
    %{
      object_type: "specs",
      events: @spec_notification_events
    }
  ]
  @notification_events Enum.flat_map(@notification_route_specs, & &1.events)
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
       scopes: [binary], allowed_team_ids: [binary]}`
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
        scopes: scopes_value(Keyword.get(conf, :scopes)),
        allowed_team_ids: allowed_team_ids_value(Keyword.get(conf, :allowed_team_ids))
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

  def notification_routes do
    Enum.map(@notification_route_specs, fn route ->
      route
      |> Map.put(:label, notification_route_label(route.object_type))
      |> Map.put(:description, notification_route_description(route.object_type))
    end)
  end

  def notification_event_label("spec.created"), do: dgettext("dashboard_slack", "New specs")

  def notification_event_label("spec.comment.created"),
    do: dgettext("dashboard_slack", "New spec comments")

  def notification_event_label("spec.review.requested"),
    do: dgettext("dashboard_slack", "Spec review requests")

  def notification_event_label(event), do: event

  defp notification_route_label("specs"), do: dgettext("dashboard_slack", "Specs")

  defp notification_route_description("specs"),
    do: dgettext("dashboard_slack", "Spec creations, comments, and review requests")

  def notification_targets_for(event) when is_binary(event) do
    case notification_route_for_event(event) do
      %{object_type: object_type} ->
        Installation
        |> where([installation], is_nil(installation.disconnected_at))
        |> where(
          [installation],
          not is_nil(installation.bot_token) and installation.bot_token != ""
        )
        |> preload(:notification_routes)
        |> Repo.all()
        |> Enum.flat_map(&target_installation(&1, object_type, event))

      _unknown_event ->
        []
    end
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

  defp allowed_team_ids_value(value), do: list_value(value)

  defp list_value(nil), do: []
  defp list_value(""), do: []

  defp list_value(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp list_value(value) when is_list(value) do
    value
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp list_value(_value), do: []

  def notification_events_for(%Installation{notification_events: events})
      when is_list(events) and events != [],
      do: events

  def notification_events_for(%Installation{}), do: default_notification_events()

  def notification_route_for(%Installation{} = installation, object_type) do
    persisted_notification_route(installation, object_type) ||
      legacy_notification_route(installation, object_type) ||
      empty_notification_route(object_type)
  end

  def update_notification_routes(%Installation{} = installation, attrs) do
    case do_update_notification_routes(installation, attrs) do
      {:ok, updated} ->
        Audit.record("slack.notification_routes.updated", %{
          target_type: "slack_installation",
          target_id: updated.id,
          target_label: updated.team_name || updated.team_id,
          metadata: %{
            team_id: updated.team_id,
            notification_routes: notification_routes_metadata(updated)
          }
        })

        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

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

  defp do_update_notification_routes(%Installation{} = installation, attrs) do
    routes_params = notification_routes_params(attrs)

    Repo.transaction(fn ->
      case save_notification_routes(installation, routes_params) do
        :ok -> get_installation(installation.id)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp save_notification_routes(%Installation{} = installation, routes_params) do
    Enum.reduce_while(notification_routes(), :ok, fn route, :ok ->
      result =
        save_notification_route(
          installation,
          route,
          route_params(routes_params, route.object_type)
        )

      case result do
        :ok -> {:cont, :ok}
        {:ok, _route} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp save_notification_route(%Installation{} = installation, route, params) do
    channel_id = params |> Map.get("slack_channel_id", "") |> normalize_route_value()

    if channel_id == "" do
      delete_notification_route(installation, route.object_type)
    else
      attrs = %{
        installation_id: installation.id,
        object_type: route.object_type,
        slack_channel_id: channel_id,
        notification_events: route.events
      }

      existing =
        Repo.get_by(NotificationRoute,
          installation_id: installation.id,
          object_type: route.object_type
        )

      (existing || %NotificationRoute{})
      |> NotificationRoute.changeset(
        attrs,
        notification_route_object_types(),
        notification_events()
      )
      |> Repo.insert_or_update()
    end
  end

  defp delete_notification_route(%Installation{} = installation, object_type) do
    NotificationRoute
    |> where([route], route.installation_id == ^installation.id)
    |> where([route], route.object_type == ^object_type)
    |> Repo.delete_all()

    :ok
  end

  defp notification_routes_params(attrs) when is_map(attrs) do
    Map.get(attrs, "notification_routes") || Map.get(attrs, :notification_routes) || %{}
  end

  defp notification_routes_params(_attrs), do: %{}

  defp route_params(routes_params, object_type) when is_map(routes_params) do
    Map.get(routes_params, object_type) || %{}
  end

  defp route_params(_routes_params, _object_type), do: %{}

  defp notification_routes_metadata(%Installation{} = installation) do
    Enum.map(notification_routes(), fn route ->
      configured_route = notification_route_for(installation, route.object_type)

      %{
        object_type: route.object_type,
        slack_channel_id: configured_route.slack_channel_id,
        notification_events: configured_route.notification_events
      }
    end)
  end

  defp target_installation(%Installation{} = installation, object_type, event) do
    with %NotificationRoute{} = route <- notification_route_for_target(installation, object_type),
         true <- notification_route_includes_event?(route, event),
         channel_id when is_binary(channel_id) and channel_id != "" <- route.slack_channel_id do
      [%{installation | notification_channel_id: channel_id}]
    else
      _not_configured -> []
    end
  end

  defp notification_route_for_target(%Installation{} = installation, object_type) do
    persisted_notification_route(installation, object_type) ||
      legacy_notification_route(installation, object_type)
  end

  defp notification_route_includes_event?(%NotificationRoute{notification_events: events}, event)
       when is_list(events) and events != [],
       do: event in events

  defp notification_route_includes_event?(%NotificationRoute{object_type: object_type}, event),
    do: event in notification_events_for_object_type(object_type)

  defp persisted_notification_route(%Installation{notification_routes: routes}, object_type)
       when is_list(routes) do
    Enum.find(routes, &(&1.object_type == object_type))
  end

  defp persisted_notification_route(
         %Installation{notification_routes: %Ecto.Association.NotLoaded{}} = installation,
         object_type
       ),
       do: persisted_notification_route_by_id(installation, object_type)

  defp persisted_notification_route(%Installation{} = installation, object_type),
    do: persisted_notification_route_by_id(installation, object_type)

  defp persisted_notification_route_by_id(%Installation{id: installation_id}, object_type)
       when is_binary(installation_id) do
    Repo.get_by(NotificationRoute, installation_id: installation_id, object_type: object_type)
  end

  defp persisted_notification_route_by_id(_installation, _object_type), do: nil

  defp legacy_notification_route(
         %Installation{notification_channel_id: channel_id} = installation,
         "specs"
       )
       when is_binary(channel_id) and channel_id != "" do
    %NotificationRoute{
      installation_id: installation.id,
      object_type: "specs",
      slack_channel_id: channel_id,
      notification_events: notification_events_for(installation)
    }
  end

  defp legacy_notification_route(_installation, _object_type), do: nil

  defp empty_notification_route(object_type) do
    %NotificationRoute{
      object_type: object_type,
      slack_channel_id: "",
      notification_events: notification_events_for_object_type(object_type)
    }
  end

  defp notification_route_for_event(event) do
    Enum.find(notification_routes(), &(event in &1.events))
  end

  defp notification_events_for_object_type(object_type) do
    notification_routes()
    |> Enum.find(&(&1.object_type == object_type))
    |> case do
      nil -> []
      route -> route.events
    end
  end

  defp notification_route_object_types do
    Enum.map(notification_routes(), & &1.object_type)
  end

  defp normalize_route_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_route_value(_value), do: ""

  @doc """
  Lists installations (most recent first), preloading the user that
  initially installed each workspace.
  """
  def list_installations do
    Installation
    |> order_by([installation], desc: installation.inserted_at)
    |> preload([:installed_by_user, :notification_routes])
    |> Repo.all()
  end

  def get_installation(nil), do: nil

  def get_installation(id),
    do: Installation |> preload([:installed_by_user, :notification_routes]) |> Repo.get(id)

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

  def linked_user_profiles_by_user_ids(%Installation{id: installation_id}, user_ids)
      when is_list(user_ids) do
    normalized_user_ids =
      user_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    SlackUser
    |> where([slack_user], slack_user.installation_id == ^installation_id)
    |> where([slack_user], slack_user.linked_user_id in ^normalized_user_ids)
    |> Repo.all()
    |> Map.new(&{&1.linked_user_id, &1})
  end

  def linked_user_profiles_by_user_ids(_installation, _user_ids), do: %{}

  def resolve_hive_user(%Installation{} = installation, slack_user_id)
      when is_binary(slack_user_id) and slack_user_id != "" do
    case linked_hive_user(installation, slack_user_id) do
      %User{} = user ->
        {:ok, user}

      nil ->
        resolve_hive_user_by_profile(installation, slack_user_id)
    end
  end

  def resolve_hive_user(_installation, _slack_user_id), do: {:error, :no_match}

  def profile_authorize_url(redirect_uri, state, opts \\ []) do
    conf = profile_authorize_config(opts)

    case conf do
      nil ->
        {:error, :not_configured}

      %{client_id: client_id} = conf ->
        query =
          %{
            "client_id" => client_id,
            "scope" => Enum.join(profile_scopes(), " "),
            "redirect_uri" => redirect_uri,
            "response_type" => "code",
            "state" => state
          }
          |> put_single_team_hint(conf)
          |> URI.encode_query()

        {:ok, "https://slack.com/openid/connect/authorize?" <> query}
    end
  end

  defp profile_authorize_config(opts) when is_list(opts),
    do: Keyword.get(opts, :config) || config()

  defp profile_authorize_config(conf), do: conf

  @doc false
  def put_single_team_hint(params, conf) when is_map(params) do
    case allowed_team_ids_value(Map.get(conf, :allowed_team_ids, [])) do
      [team_id] -> Map.put(params, "team", team_id)
      _allowed_team_ids -> params
    end
  end

  @doc false
  def validate_allowed_team_id(team_id, allowed_team_ids) do
    case allowed_team_ids_value(allowed_team_ids) do
      [] ->
        :ok

      allowed_team_ids ->
        if team_id in allowed_team_ids, do: :ok, else: {:error, :workspace_not_allowed}
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
             :ok <-
               validate_allowed_team_id(
                 attrs.installation_team_id,
                 Map.get(conf, :allowed_team_ids, [])
               ),
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
    if linked_user_id?(attrs) do
      attrs
    else
      link_hive_user_by_email(attrs)
    end
  end

  defp linked_user_id?(attrs) do
    linked_user_id = attrs[:linked_user_id] || attrs["linked_user_id"]
    is_binary(linked_user_id) and linked_user_id != ""
  end

  defp link_hive_user_by_email(attrs) do
    attrs
    |> Map.get(:email, attrs["email"])
    |> find_hive_user_by_email()
    |> case do
      nil -> attrs
      user -> Map.put(attrs, :linked_user_id, user.id)
    end
  end

  defp find_hive_user_by_email(email) when is_binary(email) and email != "" do
    Accounts.get_user_by_email(email)
  end

  defp find_hive_user_by_email(_email), do: nil

  defp linked_hive_user(%Installation{id: installation_id}, slack_user_id) do
    SlackUser
    |> where([slack_user], slack_user.installation_id == ^installation_id)
    |> where([slack_user], slack_user.slack_user_id == ^slack_user_id)
    |> preload(:linked_user)
    |> Repo.one()
    |> case do
      %SlackUser{linked_user: %User{} = user} -> user
      _other -> nil
    end
  end

  defp resolve_hive_user_by_profile(installation, slack_user_id) do
    case API.get_user(installation, slack_user_id) do
      {:ok, %{"user" => %{"profile" => %{"email" => email}}}}
      when is_binary(email) and email != "" ->
        case upsert_user(installation, %{slack_user_id: slack_user_id, email: email}) do
          {:ok, %SlackUser{} = slack_user} ->
            case Repo.preload(slack_user, :linked_user) do
              %SlackUser{linked_user: %User{} = user} -> {:ok, user}
              _other -> {:error, :no_match}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, _other} ->
        {:error, :no_match}

      {:error, reason} ->
        {:error, reason}
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
