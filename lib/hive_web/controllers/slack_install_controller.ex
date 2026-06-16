defmodule HiveWeb.SlackInstallController do
  use HiveWeb, :controller

  require Logger

  alias Hive.Accounts
  alias Hive.Slack
  alias Hive.Slack.Installations

  @state_key :slack_install_state

  def new(conn, _params) do
    if Slack.enabled?() do
      state = generate_state()
      redirect_uri = redirect_uri(conn)

      case Installations.authorize_url(redirect_uri, state, Slack.config()) do
        {:ok, url} ->
          conn
          |> put_session(@state_key, state)
          |> redirect(external: url)

        {:error, :not_configured} ->
          conn
          |> put_flash(:error, "Slack isn't configured on this Hive instance.")
          |> redirect(to: ~p"/account/slack")
      end
    else
      conn
      |> put_flash(:error, "Slack isn't configured on this Hive instance.")
      |> redirect(to: ~p"/account/slack")
    end
  end

  def callback(conn, params) do
    expected_state = get_session(conn, @state_key)

    case validate_callback(params, expected_state) do
      {:ok, code} -> complete(conn, code)
      {:error, message} -> bail(conn, message)
    end
  end

  defp validate_callback(params, expected_state) do
    state = params["state"]
    code = params["code"]

    cond do
      not is_binary(expected_state) or not is_binary(state) or expected_state != state ->
        {:error, "The Slack install link expired. Try again."}

      not is_binary(code) or code == "" ->
        {:error, "Slack didn't return an authorization code."}

      true ->
        {:ok, code}
    end
  end

  defp complete(conn, code) do
    user = current_user(conn)

    case Installations.complete_install(code, redirect_uri(conn),
           installed_by_user_id: user && user.id
         ) do
      {:ok, installation} ->
        conn
        |> delete_session(@state_key)
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

  defp bail(conn, message) do
    conn
    |> delete_session(@state_key)
    |> put_flash(:error, message)
    |> redirect(to: ~p"/account/slack")
  end

  def disconnect(conn, %{"id" => id}) do
    case Slack.get_installation(id) do
      nil ->
        conn
        |> put_flash(:error, "That Slack workspace is not connected.")
        |> redirect(to: ~p"/account/slack")

      installation ->
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
  end

  defp current_user(conn) do
    conn
    |> get_session(:user_id)
    |> Accounts.get_user()
  end

  defp generate_state do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
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
end
