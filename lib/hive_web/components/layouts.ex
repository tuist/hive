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

  attr :product_name, :string, required: true
  attr :user_name, :string, required: true
  attr :user_email, :string, default: nil
  attr :avatar_color, :string, required: true
  attr :auth_enabled?, :boolean, required: true
  attr :csrf_token, :string, required: true
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  def dashboard(assigns) do
    ~H"""
    <main class="layout">
      <header class="headerbar">
        <a class="headerbar__left" href="/">
          <div class="headerbar__brand">
            <img src={~p"/images/logo.png"} alt={@product_name} data-part="logo" />
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
      <.line_divider />
      <section class="layout__main">
        <.sidebar>
          <.sidebar_item
            label="Overview"
            icon="dashboard"
            href="/"
            selected={@current_path == "/"}
          />
        </.sidebar>
        <section class="layout__content">
          {render_slot(@inner_block)}
        </section>
      </section>
    </main>
    """
  end
end
