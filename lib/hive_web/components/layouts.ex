defmodule HiveWeb.Layouts do
  @moduledoc false

  use HiveWeb, :html

  embed_templates "layouts/*"

  attr :title, :string, required: true
  attr :open_graph, :map, default: nil
  attr :atom_feed, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title}</title>
        <.open_graph_meta open_graph={@open_graph} />
        <.atom_feed_link feed={@atom_feed} />
        <link rel="icon" type="image/png" href={~p"/images/logo.png"} />
        <link rel="stylesheet" href="/assets/js/app.css" />
      </head>
      <body data-part="app-body">
        {render_slot(@inner_block)}
      </body>
    </html>
    """
  end

  attr :feed, :map, default: nil

  def atom_feed_link(%{feed: nil} = assigns) do
    ~H""
  end

  def atom_feed_link(assigns) do
    ~H"""
    <link
      :if={@feed[:atom_href]}
      rel="alternate"
      type="application/atom+xml"
      title={@feed.title}
      href={@feed.atom_href}
    />
    <link
      :if={@feed[:rss_href]}
      rel="alternate"
      type="application/rss+xml"
      title={@feed.title}
      href={@feed.rss_href}
    />
    """
  end

  attr :flash, :map, default: %{}

  def flash_group(assigns) do
    assigns = assign(assigns, :messages, flash_messages(assigns.flash))

    ~H"""
    <div
      :if={@messages != []}
      class="flash-region"
      role="status"
      aria-live="polite"
      aria-label={dgettext("dashboard", "Status messages")}
    >
      <.alert
        :for={message <- @messages}
        id={message.id}
        type="secondary"
        status={message.status}
        size="medium"
        title={message.title}
        dismissible={true}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :atom_href, :string, required: true
  attr :rss_href, :string, required: true

  def feeds_dropdown(assigns) do
    ~H"""
    <div class="feeds-dropdown">
      <.dropdown id={@id} size="medium" icon_only={true}>
        <:icon><.icon name="rss" /></:icon>
        <.dropdown_item value="atom" label={dgettext("dashboard", "Atom")} href={@atom_href}>
          <:left_icon><.icon name="rss" /></:left_icon>
        </.dropdown_item>
        <.dropdown_item value="rss" label={dgettext("dashboard", "RSS")} href={@rss_href}>
          <:left_icon><.icon name="rss" /></:left_icon>
        </.dropdown_item>
      </.dropdown>
    </div>
    """
  end

  attr :open_graph, :map, default: nil

  def open_graph_meta(%{open_graph: nil} = assigns) do
    ~H"""
    """
  end

  def open_graph_meta(assigns) do
    ~H"""
    <meta property="og:type" content="website" />
    <meta property="og:title" content={@open_graph.title} />
    <meta property="og:description" content={@open_graph.description} />
    <meta property="og:url" content={@open_graph.url} />
    <meta property="og:image" content={@open_graph.image} />
    <meta property="og:image:type" content={HiveWeb.OpenGraph.content_type()} />
    <meta property="og:image:width" content={@open_graph.image_width} />
    <meta property="og:image:height" content={@open_graph.image_height} />
    <meta name="twitter:card" content={@open_graph.twitter_card} />
    <meta name="twitter:title" content={@open_graph.title} />
    <meta name="twitter:description" content={@open_graph.description} />
    <meta name="twitter:image" content={@open_graph.image} />
    """
  end

  attr :product_name, :string, required: true
  attr :user_name, :string, required: true
  attr :user_email, :string, default: nil
  attr :avatar_color, :string, required: true
  attr :auth_enabled?, :boolean, required: true
  attr :signed_in?, :boolean, default: false
  attr :admin?, :boolean, default: false
  attr :csrf_token, :string, required: true
  attr :current_path, :string, default: "/"
  attr :forage_sources, :list, default: []
  attr :specs_have_new_activity?, :boolean, default: false
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def dashboard(assigns) do
    ~H"""
    <main class="layout">
      <.headerbar
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
      />
      <.line_divider />
      <section data-part="main">
        <.sidebar>
          <.sidebar_item
            label={dgettext("dashboard_projects", "Projects")}
            icon="apps"
            href={~p"/projects"}
            selected={String.starts_with?(@current_path, ~p"/projects")}
          />
          <.sidebar_item
            label={dgettext("dashboard_domains", "Domains")}
            icon="treemap"
            href={~p"/domains"}
            selected={String.starts_with?(@current_path, ~p"/domains")}
          />
          <.sidebar_item
            label={dgettext("dashboard_forage", "Forage")}
            icon="rss"
            href={~p"/forage"}
            selected={String.starts_with?(@current_path, ~p"/forage")}
          />
          <.sidebar_item
            label={dgettext("dashboard_specs", "Specs")}
            icon="file_text"
            href={~p"/specs"}
            selected={String.starts_with?(@current_path, "/specs")}
            data-new-activity={if @specs_have_new_activity?, do: "true"}
          />
          <.sidebar_item
            label={dgettext("dashboard_drops", "Drops")}
            icon="package"
            href={~p"/drops"}
            selected={String.starts_with?(@current_path, ~p"/drops")}
          />
        </.sidebar>
        <section data-part="content">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </section>
      </section>
    </main>
    """
  end

  attr :product_name, :string, required: true
  attr :user_name, :string, required: true
  attr :user_email, :string, default: nil
  attr :avatar_color, :string, required: true
  attr :signed_in?, :boolean, default: false
  attr :csrf_token, :string, required: true
  attr :current_path, :string, default: "/"
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def account(assigns) do
    ~H"""
    <main class="layout">
      <.headerbar
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
      />
      <.line_divider />
      <section data-part="main">
        <.sidebar>
          <.sidebar_item
            label={dgettext("dashboard_account", "Identities")}
            icon="user"
            href={~p"/account/identities"}
            selected={String.starts_with?(@current_path, ~p"/account/identities")}
          />
        </.sidebar>
        <section data-part="content">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </section>
      </section>
    </main>
    """
  end

  attr :product_name, :string, required: true
  attr :user_name, :string, required: true
  attr :user_email, :string, default: nil
  attr :avatar_color, :string, required: true
  attr :signed_in?, :boolean, default: false
  attr :csrf_token, :string, required: true
  attr :current_path, :string, default: "/"
  attr :flash, :map, default: %{}
  slot :inner_block, required: true

  def ops(assigns) do
    ~H"""
    <main class="layout">
      <.headerbar
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
      />
      <.line_divider />
      <section data-part="main">
        <.sidebar>
          <.sidebar_item
            label={dgettext("dashboard_slack", "Slack")}
            icon="brand_slack"
            href={~p"/ops/slack"}
            selected={String.starts_with?(@current_path, ~p"/ops/slack")}
          />
          <.sidebar_item
            label={dgettext("dashboard_drops", "Drops")}
            icon="package"
            href={~p"/ops/drops"}
            selected={String.starts_with?(@current_path, ~p"/ops/drops")}
          />
          <.sidebar_item
            label={dgettext("dashboard_forage", "Forage")}
            icon="rss"
            href={~p"/ops/forage"}
            selected={String.starts_with?(@current_path, ~p"/ops/forage")}
          />
          <% inference_selected? = String.starts_with?(@current_path, ~p"/ops/inference") %>
          <details data-part="inference" open={inference_selected?}>
            <summary>
              <.tab_menu_vertical
                label={dgettext("dashboard_inference", "Inference")}
                data-selected={inference_selected?}
              >
                <:icon_left><.icon name="lock" /></:icon_left>
                <:icon_right>
                  <span data-part="indicator"><.chevron_down /></span>
                </:icon_right>
              </.tab_menu_vertical>
            </summary>
            <div data-part="content">
              <.sidebar_item
                label={dgettext("dashboard_inference", "Profiles")}
                icon="list_tree"
                href={~p"/ops/inference/profiles"}
                selected={inference_profiles_path?(@current_path)}
              />
              <.sidebar_item
                label={dgettext("dashboard_inference", "Providers")}
                icon="server"
                href={~p"/ops/inference/providers"}
                selected={@current_path == ~p"/ops/inference/providers"}
              />
            </div>
          </details>
          <.sidebar_item
            label={dgettext("dashboard_audit", "Audit")}
            icon="history"
            href={~p"/ops/audit"}
            selected={String.starts_with?(@current_path, ~p"/ops/audit")}
          />
        </.sidebar>
        <section data-part="content">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </section>
      </section>
    </main>
    """
  end

  attr :product_name, :string, required: true
  attr :user_name, :string, required: true
  attr :user_email, :string, default: nil
  attr :avatar_color, :string, required: true
  attr :signed_in?, :boolean, default: false
  attr :csrf_token, :string, required: true
  attr :current_path, :string, default: "/"

  defp headerbar(assigns) do
    ~H"""
    <header class="headerbar">
      <a data-part="left-section" href="/">
        <div data-part="brand">
          <img src={~p"/images/logo.png"} alt={@product_name} data-part="logo" />
          <span data-part="title">{@product_name}</span>
        </div>
      </a>
      <div data-part="right-section">
        <div
          :if={@signed_in?}
          id="account-dropdown"
          class="account-dropdown"
          phx-hook="NooraDropdown"
          data-loop-focus
          data-close-on-select
          data-typeahead
          data-positioning-offset-main-axis={6}
        >
          <button data-part="trigger" type="button">
            <.avatar id="current-user-avatar" name={@user_name} color={@avatar_color} size="small" />
            <span data-part="account-name">{@user_name}</span>
            <.chevron_down />
          </button>
          <div data-part="positioner">
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
              <div data-part="actions">
                <a href={~p"/account/identities"}>
                  <.user />
                  <span>{dgettext("dashboard_account", "Account")}</span>
                </a>
              </div>
              <form method="post" action="/logout" data-part="actions">
                <input type="hidden" name="_csrf_token" value={@csrf_token} />
                <input type="hidden" name="return_to" value={@current_path} />
                <button type="submit">
                  <.logout />
                  <span>{dgettext("dashboard_account", "Log out")}</span>
                </button>
              </form>
            </div>
          </div>
        </div>
        <.button
          :if={!@signed_in?}
          label={dgettext("dashboard_auth", "Sign in")}
          href={~p"/login?#{[return_to: @current_path]}"}
          variant="primary"
          size="medium"
        />
      </div>
    </header>
    """
  end

  defp flash_messages(flash) do
    [
      flash_message(flash, :info, "success"),
      flash_message(flash, :error, "error")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp flash_message(flash, key, status) do
    case flash_value(flash, key) do
      nil ->
        nil

      title ->
        %{id: "flash-#{key}", status: status, title: title}
    end
  end

  defp flash_value(flash, key) when is_map(flash) do
    flash[key] || flash[Atom.to_string(key)]
  end

  defp flash_value(_flash, _key), do: nil

  defp inference_profiles_path?(current_path) do
    current_path in [~p"/ops/inference", ~p"/ops/inference/profiles"] or
      String.starts_with?(current_path, ~p"/ops/inference/profiles/") or
      String.starts_with?(current_path, "/ops/inference/tokens/")
  end
end
