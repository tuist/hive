defmodule HiveWeb.Layouts do
  @moduledoc false

  use HiveWeb, :html

  attr :title, :string, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title}</title>
        <link rel="icon" type="image/png" href={~p"/images/logo.png"} />
        <link rel="stylesheet" href="/assets/js/app.css" />
      </head>
      <body data-part="app-body">
        {render_slot(@inner_block)}
      </body>
    </html>
    """
  end

  @doc """
  Root layout for LiveView pages: the document shell that is rendered
  once and into which each LiveView's content is diffed. Carries the
  CSRF token and the LiveSocket script.
  """
  def root(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>{assigns[:page_title] || "Hive"}</title>
        <link rel="icon" type="image/png" href={~p"/images/logo.png"} />
        <link rel="stylesheet" href="/assets/js/app.css" />
        <script defer src="/assets/js/app.js">
        </script>
      </head>
      <body data-part="app-body">
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :product_name, :string, required: true
  attr :user_name, :string, required: true
  attr :user_email, :string, default: nil
  attr :avatar_color, :string, required: true
  attr :auth_enabled?, :boolean, required: true
  attr :signed_in?, :boolean, default: false
  attr :csrf_token, :string, required: true
  attr :current_path, :string, default: "/"
  attr :forage_sources, :list, default: []
  slot :inner_block, required: true

  def dashboard(assigns) do
    ~H"""
    <main class="layout">
      <header class="headerbar">
        <a data-part="left-section" href="/">
          <div data-part="brand">
            <img src={~p"/images/logo.png"} alt={@product_name} data-part="logo" />
            <span data-part="title">{@product_name}</span>
          </div>
        </a>
        <div data-part="right-section">
          <div :if={@signed_in?} class="account-dropdown">
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
              <form method="post" action="/logout" data-part="actions">
                <input type="hidden" name="_csrf_token" value={@csrf_token} />
                <button type="submit">
                  <.logout />
                  <span>Log out</span>
                </button>
              </form>
            </div>
          </div>
          <.button
            :if={!@signed_in?}
            label="Sign in"
            href={~p"/login"}
            variant="primary"
            size="medium"
          />
        </div>
      </header>
      <.line_divider />
      <section data-part="main">
        <.sidebar>
          <details data-part="forage-sources" open>
            <summary data-part="trigger">
              <.tab_menu_vertical label="Forage">
                <:icon_left><.icon name="list_tree" /></:icon_left>
                <:icon_right>
                  <span data-part="indicator"><.chevron_down /></span>
                </:icon_right>
              </.tab_menu_vertical>
            </summary>
            <div data-part="content">
              <.sidebar_item
                :for={source <- @forage_sources}
                label={source.label}
                icon={source.icon}
                href={source.path}
                selected={String.starts_with?(@current_path, source.path)}
              />
            </div>
          </details>
        </.sidebar>
        <section data-part="content">
          {render_slot(@inner_block)}
        </section>
      </section>
    </main>
    """
  end
end
