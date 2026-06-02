defmodule HiveWeb.ForageHTML do
  @moduledoc false

  use HiveWeb, :html

  alias Hive.Auth
  alias Hive.Forage
  alias HiveWeb.Layouts

  def feature_requests_page(conn) do
    source = Forage.get_source!(:feature_requests)
    feature_requests = Forage.list_feature_requests()

    conn
    |> forage_assigns(source)
    |> Map.merge(%{feature_requests: feature_requests, stats: forage_stats(feature_requests)})
    |> feature_requests_template()
  end

  def new_feature_request_page(conn, changeset) do
    source = Forage.get_source!(:feature_requests)

    conn
    |> forage_assigns(source)
    |> Map.merge(%{form: to_form(changeset, as: :feature_request)})
    |> new_feature_request_template()
  end

  def placeholder_page(conn, source_id) do
    source = Forage.get_source!(source_id)

    conn
    |> forage_assigns(source)
    |> placeholder_template()
  end

  defp feature_requests_template(assigns) do
    ~H"""
    <Layouts.app title={"Feature requests · #{@product_name}"}>
      <Layouts.dashboard
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        auth_enabled?={@auth_enabled?}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
        forage_sources={@forage_sources}
      >
        <section id="forage">
          <.forage_header source={@source} signed_in?={@signed_in?} />

          <div data-part="widgets">
            <.forage_widget title="Total requests" value={@stats.total} legend="primary" />
            <.forage_widget title="Open" value={@stats.open} legend="secondary" />
            <.forage_widget title="Contributors" value={@stats.contributors} legend="tertiary" />
          </div>

          <.card icon={@source.icon} title={@source.label}>
            <.card_section>
              <div :if={@feature_requests == []} data-part="empty-state">
                <div data-part="empty-icon"><.bulb /></div>
                <h2>No feature requests yet</h2>
                <p>Public ideas submitted here will appear as forage for the hive.</p>
                <.button
                  label={if @signed_in?, do: "Create the first request", else: "Log in to request"}
                  href={if @signed_in?, do: ~p"/forage/feature-requests/new", else: ~p"/login"}
                  size="medium"
                  variant="secondary"
                />
              </div>

              <div :if={@feature_requests != []} data-part="request-list">
                <article :for={feature_request <- @feature_requests} data-part="request-row">
                  <div data-part="request-copy">
                    <h2>{feature_request.title}</h2>
                    <p>{feature_request.description}</p>
                    <span data-part="requester">{requester_label(feature_request)}</span>
                  </div>
                  <div data-part="request-meta">
                    <.badge
                      label={status_label(feature_request.status)}
                      color={status_color(feature_request.status)}
                      style="light-fill"
                      dot={true}
                    />
                    <.badge label="Public" color="success" style="light-fill" />
                  </div>
                </article>
              </div>
            </.card_section>
          </.card>
        </section>
      </Layouts.dashboard>
    </Layouts.app>
    """
  end

  defp new_feature_request_template(assigns) do
    ~H"""
    <Layouts.app title={"New feature request · #{@product_name}"}>
      <Layouts.dashboard
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        auth_enabled?={@auth_enabled?}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
        forage_sources={@forage_sources}
      >
        <section id="forage">
          <div data-part="header">
            <div data-part="title-group">
              <.badge label="Forage" color="information" style="light-fill" />
              <h1>New feature request</h1>
              <p>Capture a public idea that can become workable product direction.</p>
              <span data-part="requester">
                Requesting as {@user_name}
              </span>
            </div>
            <.button
              label="Back"
              href={~p"/forage/feature-requests"}
              size="medium"
              variant="secondary"
            >
              <:icon_left><.arrow_left /></:icon_left>
            </.button>
          </div>

          <.card icon="bulb" title="Request details" data-part="form-card">
            <.card_section>
              <.form for={@form} action={~p"/forage/feature-requests"} method="post" data-part="form">
                <.text_input
                  field={@form[:title]}
                  label="Title"
                  placeholder="Describe the capability in one sentence"
                  required={true}
                  show_required={true}
                />
                <.text_area
                  field={@form[:description]}
                  label="Description"
                  placeholder="Explain the problem, who needs it, and why it matters."
                  max_length={2_000}
                  rows={8}
                  required={true}
                  show_required={true}
                />
                <div data-part="form-actions">
                  <.button label="Submit request" size="medium" variant="primary" />
                </div>
              </.form>
            </.card_section>
          </.card>
        </section>
      </Layouts.dashboard>
    </Layouts.app>
    """
  end

  defp placeholder_template(assigns) do
    ~H"""
    <Layouts.app title={"#{@source.label} · #{@product_name}"}>
      <Layouts.dashboard
        product_name={@product_name}
        user_name={@user_name}
        user_email={@user_email}
        avatar_color={@avatar_color}
        auth_enabled?={@auth_enabled?}
        signed_in?={@signed_in?}
        csrf_token={@csrf_token}
        current_path={@current_path}
        forage_sources={@forage_sources}
      >
        <section id="forage">
          <.forage_header source={@source} signed_in?={@signed_in?} />
          <.card icon={@source.icon} title={@source.label}>
            <.card_section>
              <div data-part="empty-state">
                <div data-part="empty-icon"><.icon name={@source.icon} /></div>
                <h2>This forage source is not connected yet</h2>
                <p>The source is modeled so access can be gated before ingestion is implemented.</p>
              </div>
            </.card_section>
          </.card>
        </section>
      </Layouts.dashboard>
    </Layouts.app>
    """
  end

  attr :source, :map, required: true
  attr :signed_in?, :boolean, required: true

  defp forage_header(assigns) do
    ~H"""
    <div data-part="header">
      <div data-part="title-group">
        <.badge label="Forage" color="information" style="light-fill" />
        <h1>{@source.label}</h1>
        <p>{@source.description}</p>
      </div>
      <.button
        :if={@source.id == :feature_requests}
        label={if @signed_in?, do: "New request", else: "Log in to request"}
        href={if @signed_in?, do: ~p"/forage/feature-requests/new", else: ~p"/login"}
        size="medium"
        variant="primary"
      >
        <:icon_left>
          <.circle_plus :if={@signed_in?} />
          <.lock :if={!@signed_in?} />
        </:icon_left>
      </.button>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :legend, :string, default: "primary"

  defp forage_widget(assigns) do
    ~H"""
    <div data-part="widget">
      <div data-part="widget-header">
        <span data-part="legend" data-color={@legend}></span>
        <span data-part="widget-title">{@title}</span>
      </div>
      <span data-part="widget-value">{@value}</span>
    </div>
    """
  end

  defp forage_stats(feature_requests) do
    %{
      total: length(feature_requests),
      open: Enum.count(feature_requests, &(&1.status == :open)),
      contributors:
        feature_requests
        |> Enum.map(& &1.user_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()
    }
  end

  defp status_label(status), do: status |> Atom.to_string() |> String.capitalize()

  defp status_color(:open), do: "information"
  defp status_color(:planned), do: "attention"
  defp status_color(:closed), do: "neutral"

  defp forage_assigns(conn, source) do
    user = Auth.current_user(conn)
    user_name = (user && user.email) || "Guest"

    %{
      auth_enabled?: Auth.private?(),
      avatar_color: if(user_name == "Guest", do: "gray", else: "purple"),
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      current_path: conn.request_path,
      forage_sources: Forage.visible_sources(user),
      product_name: Auth.product_name(),
      signed_in?: !is_nil(user),
      source: source,
      user_email: user && user.email,
      user_name: user_name
    }
  end

  defp requester_label(%{user: %{email: email}}) when is_binary(email),
    do: "Submitted by #{email}"

  defp requester_label(_feature_request), do: "Submitted anonymously"
end
