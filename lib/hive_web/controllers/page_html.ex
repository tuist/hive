defmodule HiveWeb.PageHTML do
  @moduledoc false

  use HiveWeb, :html

  alias Hive.Auth
  alias HiveWeb.Layouts

  def login_page(conn, opts) do
    assigns = %{
      conn: conn,
      error: Keyword.get(opts, :error),
      product_name: Auth.product_name(),
      product_tagline: Auth.product_tagline(),
      auth_enabled?: Auth.enabled?(),
      provider: Auth.provider()
    }

    ~H"""
    <Layouts.app title={"Sign in · #{@product_name}"}>
      <main id="login">
        <div data-part="frame">
          <div data-part="content">
            <img src={~p"/images/logo.png"} alt={@product_name} data-part="logo" />
            <div data-part="header">
              <h1 data-part="title">Log in to {@product_name}</h1>
              <span data-part="subtitle">{@product_tagline}</span>
            </div>
            <.alert :if={@error} status="error" size="medium" title={@error} />
            <div :if={@auth_enabled? and @provider} data-part="oauth">
              <.button
                label={"Continue with #{@provider.display_name}"}
                href={~p"/auth/#{@provider.key}"}
                variant="secondary"
                size="medium"
              />
            </div>
            <div :if={@auth_enabled? and is_nil(@provider)} data-part="oauth">
              <.alert
                status="warning"
                size="large"
                title="No identity provider is configured"
                description="Set HIVE_OIDC_CLIENT_ID and the URLs (or HIVE_OIDC_PROVIDER=google with a client secret) to enable login."
              />
            </div>
            <div :if={!@auth_enabled?} data-part="oauth">
              <.alert
                status="information"
                size="large"
                title="Authentication is disabled for this environment"
                description="Set HIVE_AUTH_MODE=oidc to require an external identity provider."
              />
              <.button
                label="Continue without authentication"
                href={~p"/"}
                variant="secondary"
                size="medium"
              />
            </div>
          </div>
        </div>
        <div data-part="background" aria-hidden="true">
          <div data-part="top-right-gradient"></div>
          <div data-part="bottom-left-gradient"></div>
        </div>
      </main>
    </Layouts.app>
    """
  end

  def app_page(conn) do
    user = Auth.current_user(conn) || %{"name" => "Guest", "email" => nil}
    user_name = user["name"] || user["email"] || "Guest"

    assigns = %{
      conn: conn,
      auth_enabled?: Auth.enabled?(),
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      product_name: Auth.product_name(),
      product_tagline: Auth.product_tagline(),
      user_email: user["email"],
      user_name: user_name,
      avatar_color: if(user_name == "Guest", do: "gray", else: "purple"),
      current_path: conn.request_path
    }

    ~H"""
    <Layouts.app title={@product_name}>
      <Layouts.dashboard
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        auth_enabled?={@auth_enabled?}
        csrf_token={@csrf_token}
        current_path={@current_path}
      >
        <h1>Overview</h1>
        <p>{@product_tagline}</p>
        <.card icon="checkup_list" title="Getting started">
          <.card_section>
            <ul>
              <li>Configure authentication through environment variables.</li>
              <li>Deploy with the Helm chart and provide provider secrets.</li>
              <li>Replace placeholder modules with real product workflows.</li>
            </ul>
          </.card_section>
        </.card>
      </Layouts.dashboard>
    </Layouts.app>
    """
  end
end
