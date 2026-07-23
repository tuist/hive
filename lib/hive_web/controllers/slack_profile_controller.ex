defmodule HiveWeb.SlackProfileController do
  use HiveWeb, :controller

  require Logger

  alias Hive.Accounts
  alias Hive.Slack

  @state_salt "slack_profile"
  @state_max_age_seconds 30 * 60

  def new(conn, _params) do
    require_user(conn, fn conn, user -> authorize_profile(conn, user) end)
  end

  def callback(conn, params) do
    require_user(conn, fn conn, user -> handle_callback(conn, user, params) end)
  end

  defp require_user(conn, callback) do
    case current_user(conn) do
      nil ->
        conn
        |> put_flash(
          :error,
          dgettext("dashboard_account", "Log in to connect your Slack profile.")
        )
        |> redirect(to: ~p"/login?return_to=/account/slack/new")

      user ->
        callback.(conn, user)
    end
  end

  defp authorize_profile(conn, user) do
    if Slack.enabled?() do
      state = generate_state(conn, user)

      case Slack.profile_authorize_url(redirect_uri(conn), state, config: Slack.config()) do
        {:ok, url} ->
          redirect(conn, external: url)

        {:error, :not_configured} ->
          slack_not_configured(conn)
      end
    else
      slack_not_configured(conn)
    end
  end

  defp slack_not_configured(conn) do
    conn
    |> put_flash(
      :error,
      dgettext("dashboard_account", "Slack isn't configured on this Hive instance.")
    )
    |> redirect(to: ~p"/account/identities")
  end

  defp handle_callback(conn, user, params) do
    case validate_callback(conn, user, params) do
      {:ok, code} -> complete(conn, user, code)
      {:error, message} -> bail(conn, message)
    end
  end

  defp complete(conn, user, code) do
    case Slack.complete_profile_link(code, redirect_uri(conn), user) do
      {:ok, slack_user} ->
        conn
        |> put_flash(
          :info,
          dgettext("dashboard_account", "Connected Slack profile %{profile}.",
            profile: slack_user.slack_user_id
          )
        )
        |> redirect(to: ~p"/account/identities")

      {:error, :workspace_not_installed} ->
        bail(
          conn,
          dgettext("dashboard_account", "That Slack workspace is not connected to Hive yet.")
        )

      {:error, :workspace_not_allowed} ->
        bail(
          conn,
          dgettext(
            "dashboard_account",
            "That Slack workspace is not allowed on this Hive instance."
          )
        )

      {:error, reason} ->
        Logger.warning("[SlackProfile] OAuth exchange failed: #{inspect(reason)}")
        bail(conn, dgettext("dashboard_account", "Slack rejected the profile link. Try again."))
    end
  end

  defp validate_callback(conn, user, params) do
    with :ok <- validate_state(conn, user, params["state"]),
         :ok <- validate_slack_response(params["error"]) do
      validate_code(params["code"])
    end
  end

  defp validate_state(conn, user, state) when is_binary(state) and state != "" do
    case Phoenix.Token.verify(conn, @state_salt, state, max_age: @state_max_age_seconds) do
      {:ok, %{user_id: user_id}} when user_id == user.id ->
        :ok

      {:ok, _payload} ->
        {:error,
         dgettext(
           "dashboard_account",
           "The Slack profile link was created for a different Hive session. Try again."
         )}

      {:error, _reason} ->
        {:error, dgettext("dashboard_account", "The Slack profile link expired. Try again.")}
    end
  end

  defp validate_state(_conn, _user, _state),
    do: {:error, dgettext("dashboard_account", "The Slack profile link expired. Try again.")}

  defp validate_slack_response(error) when error in [nil, ""], do: :ok

  defp validate_slack_response("access_denied"),
    do: {:error, dgettext("dashboard_account", "Slack profile link was cancelled.")}

  defp validate_slack_response(error) when is_binary(error),
    do:
      {:error,
       dgettext("dashboard_account", "Slack rejected the profile link: %{reason}.",
         reason: format_slack_error(error)
       )}

  defp validate_code(code) when is_binary(code) and code != "", do: {:ok, code}

  defp validate_code(_code),
    do: {:error, dgettext("dashboard_account", "Slack didn't return an authorization code.")}

  defp bail(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/account/identities")
  end

  defp current_user(conn) do
    conn
    |> get_session(:user_id)
    |> Accounts.get_user()
  end

  defp generate_state(conn, user) do
    nonce =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    Phoenix.Token.sign(conn, @state_salt, %{nonce: nonce, user_id: user.id})
  end

  defp redirect_uri(conn) do
    scheme = scheme(conn)
    host = host(conn)
    "#{scheme}://#{host}/account/slack/callback"
  end

  defp scheme(conn) do
    case Application.get_env(:hive, HiveWeb.Endpoint, [])[:url] do
      [scheme: scheme] when is_binary(scheme) -> scheme
      url when is_list(url) -> url[:scheme] || Atom.to_string(conn.scheme)
      _ -> Atom.to_string(conn.scheme)
    end
  end

  defp host(conn) do
    case Application.get_env(:hive, HiveWeb.Endpoint, [])[:url] do
      url when is_list(url) ->
        case url[:host] do
          nil -> conn.host
          host -> append_port(host, url[:port])
        end

      _ ->
        case conn.port do
          80 -> conn.host
          443 -> conn.host
          port -> "#{conn.host}:#{port}"
        end
    end
  end

  defp append_port(host, port) when port in [nil, 80, 443], do: host
  defp append_port(host, port), do: "#{host}:#{port}"

  defp format_slack_error(error) do
    error
    |> String.replace("_", " ")
    |> String.trim()
  end
end
