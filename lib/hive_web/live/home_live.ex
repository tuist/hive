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
          "Follow how the product gets built, from the requests people send in to the work that ships."
        ),
      section_label: dgettext("dashboard", "Overview"),
      highlights: [
        dgettext("dashboard", "What people asked for"),
        dgettext("dashboard", "What we plan to build"),
        dgettext("dashboard", "What already shipped")
      ],
      id: "overview",
      path: "/",
      title: dgettext("dashboard", "Product development in the open")
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
      member?={@member?}
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
            <h1>{dgettext("dashboard", "Product development in the open.")}</h1>
            <p>
              {dgettext(
                "dashboard",
                "This is where the product gets built in the open: the requests people send in, the plans written from them, and the work that ships. Read any of it without an account."
              )}
            </p>
            <div data-part="hero-actions">
              <.button
                label={dgettext("dashboard_forage", "Browse the requests")}
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

          <div
            data-part="journey"
            aria-label={dgettext("dashboard", "How work moves from request to release")}
          >
            <.journey_step
              icon="rss"
              step={dgettext("dashboard", "Gather")}
              title={dgettext("dashboard", "Every signal lands here")}
              description={
                dgettext(
                  "dashboard",
                  "Feature requests, bug reports, feedback, and alerts from the people using the product."
                )
              }
            />
            <.journey_step
              icon="file_text"
              step={dgettext("dashboard", "Shape")}
              title={dgettext("dashboard", "Plans written in public")}
              description={
                dgettext(
                  "dashboard",
                  "The strongest signals turn into proposals anyone can read before they are built."
                )
              }
            />
            <.journey_step
              icon="package"
              step={dgettext("dashboard", "Deliver")}
              title={dgettext("dashboard", "Shipped work, in context")}
              description={
                dgettext(
                  "dashboard",
                  "Every release stays linked to the requests and plans it came from."
                )
              }
            />
          </div>
        </div>

        <div data-part="section-heading">
          <div>
            <span data-part="eyebrow">{dgettext("dashboard", "The product loop")}</span>
            <h2>{dgettext("dashboard", "Follow the work end to end")}</h2>
          </div>
          <p>
            {dgettext(
              "dashboard",
              "Start wherever you are curious: what people asked for, what is being planned, or what already shipped."
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
                "See what people have asked for, the bugs they hit, and the alerts being watched."
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
                "Read the proposals behind upcoming work, and the discussion that shaped each one."
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
                "Catch up on what recently reached users, and the story behind each release."
              )
            }
          />
        </div>

        <div data-part="section-heading" data-size="compact">
          <div>
            <span data-part="eyebrow">{dgettext("dashboard", "Shared context")}</span>
            <h2>{dgettext("dashboard", "Where the work lives")}</h2>
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
                "The products, codebases, and repositories all of this work belongs to."
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
                "The lasting areas of the product that requests and releases are grouped under."
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
                "When something broke: what happened, what was learned, and what changed after."
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
        {dgettext("dashboard", "Take a look")}
        <.icon name="arrow_right" />
      </span>
    </.link>
    """
  end
end
