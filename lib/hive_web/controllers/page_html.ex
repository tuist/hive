defmodule HiveWeb.PageHTML do
  @moduledoc false

  use HiveWeb, :html

  alias Hive.Auth
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  @dev_login? Application.compile_env(:hive, :dev_routes, false)

  def open_graph do
    %{
      description:
        dgettext(
          "dashboard_auth",
          "Sign in to submit public ideas and help turn domain signals into actionable work."
        ),
      section_label: Auth.product_name(),
      highlights: [
        dgettext("dashboard_auth", "OpenID Connect sign-in"),
        dgettext("dashboard_auth", "Public by default"),
        dgettext("dashboard_auth", "Organization-aware")
      ],
      id: "login",
      path: "/login",
      title: dgettext("dashboard_auth", "Log in to %{product}", product: Auth.product_name())
    }
  end

  def login_page(conn, opts) do
    open_graph = OpenGraph.assigns(open_graph())[:open_graph]

    assigns = %{
      conn: conn,
      error: Keyword.get(opts, :error),
      product_name: Auth.product_name(),
      auth_enabled?: Auth.private?(),
      providers: Auth.providers(),
      dev_login?: @dev_login?,
      dev_login_path: if(@dev_login?, do: "/dev/login"),
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      open_graph: open_graph
    }

    ~H"""
    <Layouts.app
      title={dgettext("dashboard_auth", "Sign in · %{product}", product: @product_name)}
      open_graph={@open_graph}
    >
      <main id="login">
        <div data-part="frame">
          <div data-part="content">
            <img src={~p"/images/logo.png"} alt={@product_name} data-part="logo" />
            <div data-part="header">
              <h1 data-part="title">
                {dgettext("dashboard_auth", "Log in to %{product}", product: @product_name)}
              </h1>
            </div>
            <.alert :if={@error} status="error" size="medium" title={@error} />
            <form :if={@dev_login?} method="post" action={@dev_login_path} data-part="oauth">
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <.button
                type="submit"
                label={dgettext("dashboard_auth", "Sign in as test user")}
                variant="primary"
                size="medium"
              />
            </form>
            <div :if={@providers != []} data-part="oauth">
              <.button
                :for={{key, meta} <- @providers}
                label={
                  dgettext("dashboard_auth", "Continue with %{provider}",
                    provider: meta.display_name
                  )
                }
                href={~p"/auth/#{Atom.to_string(key)}"}
                variant="secondary"
                size="medium"
              />
              <.button
                :if={!@auth_enabled?}
                label={dgettext("dashboard_auth", "Continue without signing in")}
                href={~p"/"}
                variant="secondary"
                size="medium"
              />
            </div>
            <div :if={@providers == [] and @auth_enabled?} data-part="oauth">
              <.alert
                status="warning"
                size="large"
                title={dgettext("dashboard_auth", "No identity provider is configured")}
                description={
                  dgettext(
                    "dashboard_auth",
                    "Set HIVE_GOOGLE_CLIENT_ID/HIVE_GOOGLE_CLIENT_SECRET or HIVE_OIDC_ISSUER + HIVE_OIDC_CLIENT_ID/HIVE_OIDC_CLIENT_SECRET to enable login."
                  )
                }
              />
            </div>
            <div :if={@providers == [] and !@auth_enabled?} data-part="oauth">
              <.alert
                status="information"
                size="large"
                title={dgettext("dashboard_auth", "This instance is public")}
                description={
                  dgettext(
                    "dashboard_auth",
                    "Anyone can use it without signing in. Set HIVE_VISIBILITY=private and configure an identity provider to require login."
                  )
                }
              />
              <.button
                label={dgettext("dashboard_auth", "Continue without signing in")}
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
end
