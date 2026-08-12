defmodule HiveWeb.HomeLive do
  @moduledoc false

  use HiveWeb, :live_view

  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        dgettext(
          "dashboard",
          "Bring product signals, shared plans, and shipped work into one place your whole team can follow."
        ),
      section_label: dgettext("dashboard", "Overview"),
      highlights: [
        dgettext("dashboard", "Signals in one queue"),
        dgettext("dashboard", "Shared product intent"),
        dgettext("dashboard", "Shipped work in context")
      ],
      id: "overview",
      path: "/",
      title: dgettext("dashboard", "From product signal to shipped work")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       :page_title,
       dgettext("dashboard", "Overview · %{product}", product: socket.assigns.product_name)
     )
     |> assign(OpenGraph.assigns(open_graph()))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.dashboard
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      auth_enabled?={@auth_enabled?}
      signed_in?={@signed_in?}
      admin?={@admin?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <section id="overview">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard", "Overview")}</h1>
            <p>
              {dgettext(
                "dashboard",
                "%{product} brings product signals, shared plans, and shipped improvements into one place your whole team can follow.",
                product: @product_name
              )}
            </p>
          </div>
          <div data-part="header-actions">
            <.button
              label={dgettext("dashboard_forage", "Explore Forage")}
              href={~p"/forage"}
              variant="primary"
              size="medium"
            />
          </div>
        </div>

        <.card title={dgettext("dashboard", "The product loop")} icon="arrows_exchange">
          <.card_section data-part="areas">
            <.area
              href={~p"/forage"}
              icon="rss"
              step={dgettext("dashboard", "Gather")}
              title={dgettext("dashboard_forage", "Forage")}
              description={
                dgettext(
                  "dashboard_forage",
                  "Bring feature requests, bug reports, feedback, issues, and alerts into one shared queue."
                )
              }
            />
            <.area
              href={~p"/specs"}
              icon="file_text"
              step={dgettext("dashboard", "Shape")}
              title={dgettext("dashboard_specs", "Specs")}
              description={
                dgettext(
                  "dashboard_specs",
                  "Turn evidence into clear, reviewable product intent and keep the discussion with it."
                )
              }
            />
            <.area
              href={~p"/drops"}
              icon="package"
              step={dgettext("dashboard", "Deliver")}
              title={dgettext("dashboard_drops", "Drops")}
              description={
                dgettext(
                  "dashboard_drops",
                  "See the improvements that reached users and the product context behind each release."
                )
              }
            />
          </.card_section>
        </.card>

        <.card title={dgettext("dashboard", "Shared context")} icon="category">
          <.card_section data-part="areas">
            <.area
              href={~p"/projects"}
              icon="apps"
              title={dgettext("dashboard_projects", "Projects")}
              description={
                dgettext(
                  "dashboard_projects",
                  "Group the products, codebases, repositories, and sources your organization builds."
                )
              }
            />
            <.area
              href={~p"/domains"}
              icon="treemap"
              title={dgettext("dashboard_domains", "Domains")}
              description={
                dgettext(
                  "dashboard_domains",
                  "Organize durable product areas that can span projects and collect related work."
                )
              }
            />
            <.area
              href={~p"/postmortems"}
              icon="alert_triangle"
              title={dgettext("dashboard_postmortems", "Postmortems")}
              description={
                dgettext(
                  "dashboard_postmortems",
                  "Preserve what happened, what the team learned, and the follow-up work that remains."
                )
              }
            />
          </.card_section>
        </.card>
      </section>
    </Layouts.dashboard>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :step, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp area(assigns) do
    ~H"""
    <.link navigate={@href} data-part="area">
      <span data-part="area-icon"><.icon name={@icon} /></span>
      <div data-part="area-copy">
        <div data-part="area-title">
          <span>{@title}</span>
          <.badge :if={@step} label={@step} color="primary" style="light-fill" size="small" />
        </div>
        <span data-part="area-description">{@description}</span>
      </div>
      <span data-part="area-chevron"><.icon name="chevron_right" /></span>
    </.link>
    """
  end
end
