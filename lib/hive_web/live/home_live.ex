defmodule HiveWeb.HomeLive do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Branding
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        dgettext(
          "dashboard",
          "Bring product signals, shared plans, and shipped work into one place your whole team can follow."
        ),
      section_label: dgettext("dashboard", "Hive overview"),
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
        <div data-part="hero">
          <div data-part="hero-copy">
            <div data-part="product-mark">
              <img src={Branding.logo_url()} alt="" />
              <span>{@product_name}</span>
            </div>
            <h1>{dgettext("dashboard", "From product signal to shipped work.")}</h1>
            <p>
              {dgettext(
                "dashboard",
                "Hive brings product signals, shared plans, and shipped improvements into one place your whole team can follow."
              )}
            </p>
            <div data-part="hero-actions">
              <.button
                label={dgettext("dashboard_forage", "Explore Forage")}
                href={~p"/forage"}
                variant="primary"
                size="medium"
              />
              <.button
                label={dgettext("dashboard_drops", "See what shipped")}
                href={~p"/drops"}
                variant="secondary"
                size="medium"
              />
            </div>
          </div>

          <div data-part="journey" aria-label={dgettext("dashboard", "How work moves through Hive")}>
            <.journey_step
              icon="rss"
              step={dgettext("dashboard", "Gather")}
              title={dgettext("dashboard", "Listen to every signal")}
              description={
                dgettext("dashboard", "Requests, feedback, issues, and alerts arrive with context.")
              }
            />
            <.journey_step
              icon="file_text"
              step={dgettext("dashboard", "Shape")}
              title={dgettext("dashboard", "Make intent explicit")}
              description={
                dgettext("dashboard", "Evidence becomes a proposal the whole team can discuss.")
              }
            />
            <.journey_step
              icon="package"
              step={dgettext("dashboard", "Deliver")}
              title={dgettext("dashboard", "Close the loop")}
              description={
                dgettext("dashboard", "Shipped improvements stay connected to the work behind them.")
              }
            />
          </div>
        </div>

        <div data-part="section-heading">
          <div>
            <span data-part="eyebrow">{dgettext("dashboard", "The product loop")}</span>
            <h2>{dgettext("dashboard", "Choose where to start")}</h2>
          </div>
          <p>
            {dgettext(
              "dashboard",
              "Follow work from evidence to outcome, or jump directly into the part you need."
            )}
          </p>
        </div>

        <div data-part="primary-grid">
          <.area_card
            href={~p"/forage"}
            icon="rss"
            number="01"
            title={dgettext("dashboard_forage", "Forage")}
            description={
              dgettext(
                "dashboard_forage",
                "Bring feature requests, bug reports, feedback, issues, and alerts into one shared queue."
              )
            }
          />
          <.area_card
            href={~p"/specs"}
            icon="file_text"
            number="02"
            title={dgettext("dashboard_specs", "Specs")}
            description={
              dgettext(
                "dashboard_specs",
                "Turn evidence into clear, reviewable product intent and keep the discussion with it."
              )
            }
          />
          <.area_card
            href={~p"/drops"}
            icon="package"
            number="03"
            title={dgettext("dashboard_drops", "Drops")}
            description={
              dgettext(
                "dashboard_drops",
                "See the improvements that reached users and the product context behind each release."
              )
            }
          />
        </div>

        <div data-part="section-heading" data-size="compact">
          <div>
            <span data-part="eyebrow">{dgettext("dashboard", "Shared context")}</span>
            <h2>{dgettext("dashboard", "Keep the work connected")}</h2>
          </div>
        </div>

        <div data-part="secondary-grid">
          <.area_card
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
          <.area_card
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
          <.area_card
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
        </div>
      </section>
    </Layouts.dashboard>
    """
  end

  attr :icon, :string, required: true
  attr :step, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp journey_step(assigns) do
    ~H"""
    <div data-part="journey-step">
      <span data-part="journey-icon"><.icon name={@icon} /></span>
      <div data-part="journey-copy">
        <span data-part="journey-label">{@step}</span>
        <strong>{@title}</strong>
        <p>{@description}</p>
      </div>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :number, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, required: true

  defp area_card(assigns) do
    ~H"""
    <.link navigate={@href} data-part="area-card">
      <div data-part="area-card-header">
        <span data-part="area-icon"><.icon name={@icon} /></span>
        <span :if={@number} data-part="area-number">{@number}</span>
      </div>
      <div data-part="area-copy">
        <h3>{@title}</h3>
        <p>{@description}</p>
      </div>
      <span data-part="area-action">
        {dgettext("dashboard", "Explore")}
        <.icon name="arrow_right" />
      </span>
    </.link>
    """
  end
end
