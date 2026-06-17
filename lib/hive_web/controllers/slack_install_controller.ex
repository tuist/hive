defmodule HiveWeb.SlackInstallController do
  use HiveWeb, :controller

  require Logger

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Slack
  alias Hive.Slack.Installations

  @state_salt "slack_install"
  @state_max_age_seconds 30 * 60

  def new(conn, _params) do
    require_member(conn, fn conn, user -> start_install(conn, user) end)
  end

  def callback(conn, params) do
    require_member(conn, fn conn, user -> handle_callback(conn, user, params) end)
  end

  def disconnect(conn, %{"id" => id}) do
    require_member(conn, fn conn, _user -> disconnect_installation(conn, id) end)
  end

  defp require_member(conn, callback) do
    case current_user(conn) do
      nil -> require_member_login(conn)
      user -> require_member_role(conn, user, callback)
    end
  end

  defp require_member_login(conn) do
    conn
    |> put_flash(:error, "Log in to manage Slack workspaces.")
    |> redirect(to: ~p"/login")
  end

  defp require_member_role(conn, user, callback) do
    if Auth.member?(user) do
      callback.(conn, user)
    else
      conn
      |> put_flash(:error, "Only organization members can manage Slack workspaces.")
      |> redirect(to: ~p"/account/identities")
    end
  end

  defp start_install(conn, user) do
    if Slack.enabled?() do
      authorize_install(conn, user)
    else
      slack_not_configured(conn)
    end
  end

  defp authorize_install(conn, user) do
    state = generate_state(conn, user)
    redirect_uri = redirect_uri(conn)

    case Installations.authorize_url(redirect_uri, state, Slack.config()) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, :not_configured} ->
        slack_not_configured(conn)
    end
  end

  defp slack_not_configured(conn) do
    conn
    |> put_flash(:error, "Slack isn't configured on this Hive instance.")
    |> redirect(to: ~p"/account/slack")
  end

  defp handle_callback(conn, user, params) do
    case validate_callback(conn, user, params) do
      {:ok, code} -> complete(conn, user, code)
      {:error, message} -> bail(conn, message)
    end
  end

  defp complete(conn, user, code) do
    case Installations.complete_install(code, redirect_uri(conn), installed_by_user_id: user.id) do
      {:ok, installation} ->
        conn
        |> put_flash(
          :info,
          "Connected #{installation.team_name || installation.team_id} to Hive."
        )
        |> redirect(to: ~p"/account/slack")

      {:error, reason} ->
        Logger.warning("[SlackInstall] OAuth exchange failed: #{inspect(reason)}")
        bail(conn, "Slack rejected the install. Try again.")
    end
  end

  defp disconnect_installation(conn, id) when is_binary(id) do
    case Slack.get_installation(id) do
      nil -> missing_installation(conn)
      installation -> disconnect_installation(conn, installation)
    end
  end

  defp disconnect_installation(conn, installation) do
    case Installations.disconnect(installation) do
      {:ok, updated} ->
        conn
        |> put_flash(
          :info,
          "Disconnected #{updated.team_name || updated.team_id} from Hive."
        )
        |> redirect(to: ~p"/account/slack")

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not disconnect that workspace.")
        |> redirect(to: ~p"/account/slack")
    end
  end

  defp missing_installation(conn) do
    conn
    |> put_flash(:error, "That Slack workspace is not connected.")
    |> redirect(to: ~p"/account/slack")
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
        {:error, "The Slack install link was created for a different Hive session. Try again."}

      {:error, _reason} ->
        {:error, "The Slack install link expired. Try again."}
    end
  end

  defp validate_state(_conn, _user, _state),
    do: {:error, "The Slack install link expired. Try again."}

  defp validate_slack_response(error) when error in [nil, ""], do: :ok

  defp validate_slack_response("access_denied"),
    do: {:error, "Slack install was cancelled."}

  defp validate_slack_response(error) when is_binary(error),
    do: {:error, "Slack rejected the install: #{format_slack_error(error)}."}

  defp validate_code(code) when is_binary(code) and code != "", do: {:ok, code}

  defp validate_code(_code), do: {:error, "Slack didn't return an authorization code."}

  defp bail(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/account/slack")
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
    "#{scheme}://#{host}/slack/install/callback"
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
