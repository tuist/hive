defmodule HiveWeb.AuthController do
  use HiveWeb, :controller

  alias Hive.Accounts
  alias Hive.Audit
  alias Hive.Auth
  alias HiveWeb.PageHTML

  def new(conn, params) do
    conn
    |> maybe_store_return_to(params)
    |> html(Phoenix.HTML.Safe.to_iodata(PageHTML.login_page(conn, error: nil)))
  end

  # Ueberauth's plug normally handles the redirect to the IdP before this
  # action runs. Keep a fallback here so a configured provider still starts
  # when the plug route table falls through.
  def request(conn, %{"provider" => provider_key}) do
    with key when is_atom(key) <- safe_atom(provider_key),
         provider when not is_nil(provider) <- Auth.provider(key),
         ueberauth_provider when not is_nil(ueberauth_provider) <-
           Auth.ueberauth_provider(key) do
      Ueberauth.run_request(conn, provider_key, ueberauth_provider)
    else
      _ -> unauthorized(conn, "The login attempt could not be started.")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    unauthorized(conn, "The login attempt could not be completed.")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider_key}) do
    email = auth.info.email

    with key when is_atom(key) <- safe_atom(provider_key),
         provider when not is_nil(provider) <- Auth.provider(key),
         :ok <- Auth.check_domain(provider, email || "") do
      auth_attrs = %{
        email: email,
        name: auth.info.name,
        provider: provider_key,
        provider_uid: to_string(auth.uid)
      }

      case current_user(conn) do
        nil -> sign_in_from_auth(conn, auth_attrs)
        user -> link_identity(conn, user, auth_attrs, provider.display_name)
      end
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

  def dev_login(conn, _params) do
    if Application.get_env(:hive, :dev_routes, false) do
      {:ok, user} =
        case Accounts.get_user_by_email("test@hive.dev") do
          nil ->
            Accounts.upsert_from_auth(%{
              email: "test@hive.dev",
              provider: "dev",
              provider_uid: "test@hive.dev"
            })

          user ->
            {:ok, user}
        end

      {:ok, user} = Accounts.update_user_role(user, :admin)

      sign_in(conn, user)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(:not_found, "Not found")
    end
  end

  def delete(conn, params) do
    return_to = logout_return_to(params)

    case current_user(conn) do
      nil ->
        :ok

      user ->
        Audit.record("user.signed_out", %{
          actor: user,
          interface: "dashboard",
          target_type: "user",
          target_id: user.id,
          target_label: user.email
        })
    end

    conn
    |> configure_session(drop: true)
    |> redirect(to: return_to)
  end

  defp sign_in(conn, user) do
    return_to = get_session(conn, :user_return_to) || ~p"/"

    Audit.record("user.signed_in", %{
      actor: user,
      interface: "dashboard",
      target_type: "user",
      target_id: user.id,
      target_label: user.email
    })

    conn
    |> configure_session(renew: true)
    |> put_session(:user_id, user.id)
    |> delete_session(:user_return_to)
    |> redirect(to: return_to)
  end

  defp maybe_store_return_to(conn, %{"return_to" => return_to}) do
    if local_return_to?(return_to) do
      put_session(conn, :user_return_to, return_to)
    else
      conn
    end
  end

  defp maybe_store_return_to(conn, _params), do: conn

  defp logout_return_to(%{"return_to" => return_to}) do
    if local_return_to?(return_to), do: return_to, else: ~p"/login"
  end

  defp logout_return_to(_params), do: ~p"/login"

  defp local_return_to?(return_to) when is_binary(return_to) do
    uri = URI.parse(return_to)

    String.starts_with?(return_to, "/") and not String.starts_with?(return_to, "//") and
      is_nil(uri.scheme) and is_nil(uri.host)
  end

  defp local_return_to?(_return_to), do: false

  defp sign_in_from_auth(conn, attrs) do
    case Accounts.upsert_from_auth(attrs) do
      {:ok, user} ->
        sign_in(conn, user)

      {:error, %Ecto.Changeset{}} ->
        unauthorized(conn, "We couldn't read a usable email from your account.")
    end
  end

  defp link_identity(conn, user, attrs, provider_name) do
    case Accounts.link_identity(user, attrs) do
      {:ok, user} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "#{provider_name} is connected to your account.")
        |> redirect(to: ~p"/account/identities")

      {:error, :identity_already_linked} ->
        conn
        |> put_flash(:error, "#{provider_name} is already connected to another account.")
        |> redirect(to: ~p"/account/identities")

      {:error, %Ecto.Changeset{}} ->
        unauthorized(conn, "We couldn't connect that identity to your account.")
    end
  end

  defp current_user(conn) do
    conn
    |> get_session(:user_id)
    |> Accounts.get_user()
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
