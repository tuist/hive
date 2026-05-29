defmodule HiveWeb.AuthController do
  use HiveWeb, :controller

  alias Hive.Auth
  alias HiveWeb.PageHTML

  def new(conn, _params) do
    html(conn, Phoenix.HTML.Safe.to_iodata(PageHTML.login_page(conn, error: nil)))
  end

  # Ueberauth's plug handles the redirect to the IdP before this action
  # runs; it should never actually execute.
  def request(conn, _params) do
    unauthorized(conn, "The login attempt could not be started.")
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    unauthorized(conn, "The login attempt could not be completed.")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider_key}) do
    user = %{
      "email" => auth.info.email,
      "name" => auth.info.name || auth.info.nickname || auth.info.email || "Authenticated user"
    }

    with key when is_atom(key) <- safe_atom(provider_key),
         :ok <- Auth.check_domain(key, user["email"] || "") do
      conn
      |> configure_session(renew: true)
      |> put_session(:current_user, user)
      |> redirect(to: ~p"/")
    else
      {:error, :domain_not_allowed} ->
        unauthorized(conn, "Your account isn't from an allowed domain for this instance.")

      _ ->
        unauthorized(conn, "Unknown identity provider.")
    end
  end

  def callback(conn, _params) do
    unauthorized(conn, "The login callback was missing required parameters.")
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end

  defp safe_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> nil
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> html(Phoenix.HTML.Safe.to_iodata(PageHTML.login_page(conn, error: message)))
  end
end
