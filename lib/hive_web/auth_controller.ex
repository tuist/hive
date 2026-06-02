defmodule HiveWeb.AuthController do
  use HiveWeb, :controller

  alias Hive.Accounts
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
    email = auth.info.email

    with key when is_atom(key) <- safe_atom(provider_key),
         provider when not is_nil(provider) <- Auth.provider(key),
         :ok <- Auth.check_domain(provider, email || ""),
         {:ok, user} <-
           Accounts.upsert_from_auth(%{
             email: email,
             provider: provider_key,
             provider_uid: to_string(auth.uid)
           }) do
      sign_in(conn, user)
    else
      {:error, :domain_not_allowed} ->
        unauthorized(conn, "Your account isn't from an allowed domain for this instance.")

      {:error, %Ecto.Changeset{}} ->
        unauthorized(conn, "We couldn't read a usable email from your account.")

      _ ->
        unauthorized(conn, "Unknown identity provider.")
    end
  end

  def callback(conn, _params) do
    unauthorized(conn, "The login callback was missing required parameters.")
  end

  def dev_login(conn, _params) do
    if Application.get_env(:hive, :dev_routes, false) do
      {:ok, user} =
        Accounts.upsert_from_auth(%{
          email: "test@hive.dev",
          provider: "dev",
          provider_uid: "dev"
        })

      sign_in(conn, user)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:not_found, "Not found")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end

  defp sign_in(conn, user) do
    conn
    |> configure_session(renew: true)
    |> put_session(:user_id, user.id)
    |> redirect(to: ~p"/")
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
