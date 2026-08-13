defmodule HiveWeb.OAuth.AuthorizeHTML do
  @moduledoc false

  use HiveWeb, :html

  alias Hive.Branding
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description:
        dgettext(
          "dashboard_auth",
          "Review and approve a secure application access request."
        ),
      section_label: Branding.product_name(),
      highlights: [
        dgettext("dashboard_auth", "You stay in control"),
        dgettext("dashboard_auth", "Access can be revoked"),
        dgettext("dashboard_auth", "Secure browser handoff")
      ],
      id: "authorization-consent",
      path: "/oauth2/authorize",
      title: dgettext("dashboard_auth", "Authorize application access")
    }
  end

  def consent_page(conn, authorization, opts) do
    assigns = %{
      action: Phoenix.Controller.current_path(conn),
      client_name:
        authorization.client.name || dgettext("dashboard_auth", "Connected application"),
      csrf_token: Keyword.fetch!(opts, :csrf_token),
      open_graph: OpenGraph.assigns(open_graph())[:open_graph],
      redirect_uri: authorization.redirect_uri || "",
      scope: scope_label(authorization.scope || ""),
      user: authorization.resource_owner.username
    }

    ~H"""
    <Layouts.app
      title={dgettext("dashboard_auth", "Authorize %{client} · Hive", client: @client_name)}
      open_graph={@open_graph}
    >
      <main id="oauth-consent">
        <div data-part="frame">
          <div data-part="brand">
            <img src={Branding.logo_url()} alt={Branding.product_name()} data-part="logo" />
            <span data-part="brand-name">{Branding.product_name()}</span>
          </div>

          <div data-part="header">
            <div data-part="app-icon" aria-hidden="true">
              <.icon name="device_mobile" />
            </div>
            <div data-part="heading">
              <p data-part="eyebrow">{dgettext("dashboard_auth", "Authorization request")}</p>
              <h1 data-part="title">
                {dgettext("dashboard_auth", "Authorize %{client}", client: @client_name)}
              </h1>
              <p data-part="description">
                {dgettext("dashboard_auth", "Continue as %{user}", user: @user)}
              </p>
            </div>
          </div>

          <section data-part="permission" aria-labelledby="permission-title">
            <div data-part="permission-icon" aria-hidden="true">
              <.icon name="lock" />
            </div>
            <div data-part="permission-copy">
              <h2 id="permission-title">
                {dgettext("dashboard_auth", "Use Hive on your behalf")}
              </h2>
              <p>
                {dgettext(
                  "dashboard_auth",
                  "This application will be able to access the Hive content available to your account."
                )}
              </p>
            </div>
          </section>

          <dl data-part="client-info">
            <div data-part="client-info-row">
              <dt data-part="client-info-label">{dgettext("dashboard_auth", "Access")}</dt>
              <dd data-part="client-info-value">{@scope}</dd>
            </div>
            <div data-part="client-info-row">
              <dt data-part="client-info-label">{dgettext("dashboard_auth", "Returns to")}</dt>
              <dd data-part="client-info-value">{@redirect_uri}</dd>
            </div>
          </dl>

          <p data-part="notice">
            {dgettext(
              "dashboard_auth",
              "Only continue if you recognize this application. You can revoke access later from your account."
            )}
          </p>

          <div data-part="actions">
            <form data-part="form" method="post" action={@action}>
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="decision" value="approve" />
              <.button
                data-part="approve-button"
                type="submit"
                label={dgettext("dashboard_auth", "Allow access")}
                variant="primary"
                size="large"
              />
            </form>
            <form data-part="form" method="post" action={@action}>
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="decision" value="deny" />
              <.button
                data-part="deny-button"
                type="submit"
                label={dgettext("dashboard_auth", "Cancel")}
                variant="secondary"
                size="large"
              />
            </form>
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

  def denied_page do
    assigns = %{open_graph: OpenGraph.assigns(open_graph())[:open_graph]}

    ~H"""
    <Layouts.app title={dgettext("dashboard_auth", "Access not granted · %{product}", product: Branding.product_name())} open_graph={@open_graph}>
      <main id="oauth-consent">
        <div data-part="frame" data-state="denied">
          <div data-part="brand">
            <img src={Branding.logo_url()} alt={Branding.product_name()} data-part="logo" />
            <span data-part="brand-name">{Branding.product_name()}</span>
          </div>
          <div data-part="result-icon" aria-hidden="true"><.icon name="lock" /></div>
          <div data-part="result-copy">
            <h1>{dgettext("dashboard_auth", "Access was not granted")}</h1>
            <p>{dgettext("dashboard_auth", "You can close this window and return to the application.")}</p>
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

  defp scope_label("mobile"), do: dgettext("dashboard_auth", "Mobile app access")

  defp scope_label("mcp"),
    do: dgettext("dashboard_auth", "Model Context Protocol access")

  defp scope_label(scope), do: scope
end
