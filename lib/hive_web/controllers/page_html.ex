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
        "Sign in to submit public ideas and help turn domain signals into actionable work.",
      eyebrow: Auth.product_name(),
      highlights: ["OIDC sign-in", "Public by default", "Organization-aware"],
      id: "login",
      path: "/login",
      title: "Log in to #{Auth.product_name()}"
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
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      open_graph: open_graph
    }

    ~H"""
    <Layouts.app title={"Sign in · #{@product_name}"} open_graph={@open_graph}>
      <main id="login">
        <div data-part="frame">
          <div data-part="content">
            <img src={~p"/images/logo.png"} alt={@product_name} data-part="logo" />
            <div data-part="header">
              <h1 data-part="title">Log in to {@product_name}</h1>
            </div>
            <.alert :if={@error} status="error" size="medium" title={@error} />
            <form :if={@dev_login?} method="post" action={~p"/dev/login"} data-part="oauth">
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <.button
                type="submit"
                label="Sign in as test user"
                variant="primary"
                size="medium"
              />
            </form>
            <div :if={@providers != []} data-part="oauth">
              <.button
                :for={{key, meta} <- @providers}
                label={"Continue with #{meta.display_name}"}
                href={~p"/auth/#{Atom.to_string(key)}"}
                variant="secondary"
                size="medium"
              />
              <.button
                :if={!@auth_enabled?}
                label="Continue without signing in"
                href={~p"/"}
                variant="secondary"
                size="medium"
              />
            </div>
            <div :if={@providers == [] and @auth_enabled?} data-part="oauth">
              <.alert
                status="warning"
                size="large"
                title="No identity provider is configured"
                description="Set HIVE_GOOGLE_CLIENT_ID/HIVE_GOOGLE_CLIENT_SECRET or HIVE_OIDC_ISSUER + HIVE_OIDC_CLIENT_ID/HIVE_OIDC_CLIENT_SECRET to enable login."
              />
            </div>
            <div :if={@providers == [] and !@auth_enabled?} data-part="oauth">
              <.alert
                status="information"
                size="large"
                title="This instance is public"
                description="Anyone can use it without signing in. Set HIVE_VISIBILITY=private and configure an identity provider to require login."
              />
              <.button
                label="Continue without signing in"
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
