defmodule HiveWeb.PageHTML do
  @moduledoc false

  use HiveWeb, :html

  alias Hive.Auth

  def login_page(conn, opts) do
    assigns = %{
      conn: conn,
      error: Keyword.get(opts, :error),
      product_name: Auth.product_name(),
      product_tagline: Auth.product_tagline(),
      provider_name: Auth.provider_name(),
      auth_enabled?: Auth.enabled?()
    }

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <.head title={"Sign in · #{@product_name}"} />
      </head>
      <body>
        <main id="login">
          <div data-part="frame">
            <div data-part="content">
              <div data-part="logo" aria-hidden="true">H</div>
              <div data-part="header">
                <h1 data-part="title">Log in to {@product_name}</h1>
                <span data-part="subtitle">{@product_tagline}</span>
              </div>
              <.alert :if={@error} status="error" size="medium" title={@error} />
              <div :if={@auth_enabled?} data-part="oauth">
                <.button
                  label={"Continue with #{@provider_name}"}
                  href={~p"/auth/oidc"}
                  variant="secondary"
                  size="medium"
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
      </body>
    </html>
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
      avatar_color: if(user_name == "Guest", do: "gray", else: "purple")
    }

    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <.head title={@product_name} />
      </head>
      <body data-part="app-body">
        <main class="layout">
          <header class="headerbar">
            <a class="headerbar__left" href="/">
              <div class="headerbar__brand">
                <div data-part="logo" aria-hidden="true">H</div>
                <span class="headerbar__title">{@product_name}</span>
              </div>
            </a>
            <div class="headerbar__right">
              <div class="account-dropdown">
                <button data-part="trigger" type="button">
                  <.avatar
                    id="current-user-avatar"
                    name={@user_name}
                    color={@avatar_color}
                    size="small"
                  />
                  <span data-part="account-name">{@user_name}</span>
                  <.chevron_down />
                </button>
                <div data-part="content">
                  <div data-part="header">
                    <.avatar
                      id="current-user-menu-avatar"
                      name={@user_name}
                      color={@avatar_color}
                      size="medium"
                    />
                    <div data-part="identity">
                      <span data-part="name">{@user_name}</span>
                      <span :if={@user_email} data-part="email">{@user_email}</span>
                    </div>
                  </div>
                  <form :if={@auth_enabled?} method="post" action="/logout" data-part="actions">
                    <input type="hidden" name="_csrf_token" value={@csrf_token} />
                    <button type="submit">
                      <.logout />
                      <span>Log out</span>
                    </button>
                  </form>
                  <div :if={!@auth_enabled?} data-part="actions">
                    <a href={~p"/login"}>
                      <.settings />
                      <span>Auth setup</span>
                    </a>
                  </div>
                </div>
              </div>
            </div>
            </header>
          <div data-part="line-divider"></div>
          <section class="layout__main">
            <.sidebar>
              <.sidebar_item label="Overview" icon="dashboard" href="/" selected />
              <.sidebar_group
                id="work-group"
                label="Workspace"
                icon="layout_grid"
                collapsible={true}
                default_open={true}
              >
                <.sidebar_item label="Work streams" icon="list_tree" href="/" />
                <.sidebar_item label="Decisions" icon="circle_check" href="/" />
              </.sidebar_group>
              <.sidebar_group
                id="admin-group"
                label="Operations"
                icon="settings"
                collapsible={true}
                default_open={true}
              >
                <.sidebar_item label="Settings" icon="settings" href={~p"/login"} />
              </.sidebar_group>
            </.sidebar>
            <section class="layout__content">
              <div data-part="page-heading">
                <.badge label="Workspace" color="neutral" style="light-fill" />
                <h1>Product orchestration</h1>
                <p>{@product_tagline}</p>
              </div>
              <div data-part="hive-dashboard">
                <section data-part="hero">
                  <.badge label="Today" color="primary" style="light-fill" size="large" />
                  <h2>Keep product work visible, owned, and moving.</h2>
                  <p>
                    Connect data sources, define work streams, and give contributors a single place
                    to understand what needs attention.
                  </p>
                </section>
                <.card icon="layout_grid" title="Active work streams">
                  <.card_section class="metric-card">
                    <strong>0</strong>
                    <span>Streams configured</span>
                  </.card_section>
                </.card>
                <.card icon="circle_check" title="Open decisions">
                  <.card_section class="metric-card">
                    <strong>0</strong>
                    <span>Decisions pending</span>
                  </.card_section>
                </.card>
                <.card icon="settings" title="Getting started" class="wide-card">
                  <.card_section>
                    <ul data-part="task-list">
                      <li><span></span> Configure authentication through environment variables.</li>
                      <li><span></span> Deploy with the Helm chart and provide provider secrets.</li>
                      <li><span></span> Replace placeholder modules with real product workflows.</li>
                    </ul>
                  </.card_section>
                </.card>
              </div>
            </section>
          </section>
        </main>
      </body>
    </html>
    """
  end

  attr(:title, :string, required: true)

  defp head(assigns) do
    ~H"""
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{@title}</title>
    <link rel="stylesheet" href="/assets/js/app.css" />
    """
  end
end
