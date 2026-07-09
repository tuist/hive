defmodule HiveWeb.OpsLive.InferenceToken do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Audit
  alias Hive.Inference
  alias Hive.Inference.ModelBinding
  alias Hive.Inference.Token
  alias Hive.Ops.Policy
  alias HiveWeb.Components.EmptyCardSection
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query

  import EmptyCardSection
  import HiveWeb.OpsLive.InferenceHelpers

  def open_graph(%Token{} = token, %ModelBinding{} = profile) do
    %{
      description:
        dgettext("dashboard_inference", "Review usage for the %{token} inference token.",
          token: token.name
        ),
      section_label: dgettext("dashboard_inference", "Ops"),
      highlights: [
        dgettext("dashboard_inference", "Token usage"),
        dgettext("dashboard_inference", "Input and output tokens"),
        dgettext("dashboard_inference", "Estimated cost")
      ],
      id: "ops-inference-token",
      path: "/ops/inference/tokens/#{token.id}",
      title: token.name,
      type_label: profile.name
    }
  end

  def slack_unfurl(uri, _params) do
    Hive.Slack.Unfurl.BlockKit.generic(uri, %{
      description: dgettext("dashboard_inference", "Review usage for an inference token."),
      highlights: [
        dgettext("dashboard_inference", "Token usage"),
        dgettext("dashboard_inference", "Input and output tokens"),
        dgettext("dashboard_inference", "Estimated cost")
      ],
      section_label: dgettext("dashboard_inference", "Ops"),
      title: dgettext("dashboard_inference", "Inference token")
    })
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_inference", "Log in to manage inference tokens.")
         )
         |> redirect(to: ~p"/login?#{[return_to: "/ops/inference/tokens/#{id}"]}")}

      not Policy.authorize?(:inference_profile_manage, user, nil) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_inference", "Only instance admins can manage inference tokens.")
         )
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok, assign_token(socket, id)}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    {preset, period} = usage_period_from_params(params)

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:usage_preset, preset)
     |> assign(:usage_period, period)
     |> assign_usage()}
  end

  @impl true
  def handle_event("usage_period_changed", params, socket) do
    preset = params["preset"] || "last-30-days"
    value = params["value"] || %{}

    {:noreply,
     push_patch(socket,
       to: usage_period_patch(socket.assigns.token, socket.assigns.uri, preset, value)
     )}
  end

  def handle_event("revoke_token", _params, socket) do
    token = socket.assigns.token
    profile = socket.assigns.profile

    case Inference.revoke_token(token) do
      {:ok, token} ->
        record_token_audit(:"inference_token.revoked", profile, token)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_inference", "Token revoked."))
         |> push_event("close-modal", %{id: "revoke-inference-token-modal"})
         |> assign_token(token.id)}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, dgettext("dashboard_inference", "Failed to revoke token."))}
    end
  end

  def handle_event("close_revoke_token", _params, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: "revoke-inference-token-modal"})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.ops
      flash={@flash}
      product_name={@product_name}
      user_name={@user_name}
      user_email={@user_email}
      avatar_color={@avatar_color}
      signed_in?={@signed_in?}
      csrf_token={@csrf_token}
      current_path={@current_path}
    >
      <section id="ops-inference-token">
        <div data-part="page-header">
          <div data-part="title-group">
            <h1>{@token.name}</h1>
            <p>
              {dgettext("dashboard_inference", "Token bound to")}
              <a href={~p"/ops/inference/profiles/#{@profile.id}"}>{@profile.name}</a>.
            </p>
          </div>
        </div>

        <.card title={dgettext("dashboard_inference", "Usage")} icon="chart_column" data-part="usage-card">
          <:actions>
            <.usage_period_picker
              id="inference-token-usage-date-range-picker"
              name="usage-date-range"
              selected_preset={@usage_preset}
              period={@usage_period}
            />
          </:actions>
          <.card_section>
            <.usage_widgets summary={@usage_summary} />
          </.card_section>
          <.card_section
            :if={usage_chart_has_usage?(@usage_series)}
            data-part="usage-chart-section"
          >
            <.usage_chart
              id="inference-token-usage-chart"
              series={@usage_series}
              preset={@usage_preset}
              bucket={@usage_bucket}
              label={
                dgettext("dashboard_inference", "Input and output token usage for %{token}",
                  token: @token.name
                )
              }
            />
          </.card_section>
          <.empty_card_section
            :if={!usage_chart_has_usage?(@usage_series)}
            title={dgettext("dashboard_inference", "No usage yet")}
            data-part="empty-usage-chart-card-section"
          >
            <:image>
              <img src="/images/empty_line_chart_light.png" data-theme="light" />
              <img src="/images/empty_line_chart_dark.png" data-theme="dark" />
            </:image>
          </.empty_card_section>
        </.card>

        <.card
          title={dgettext("dashboard_inference", "Configuration")}
          icon="lock_password"
          data-part="configuration-card"
        >
          <.card_section>
            <div data-part="definition-grid">
              <div data-part="definition-item">
                <span>{dgettext("dashboard_inference", "Status")}</span>
                <% status = token_status(@token) %>
                <.badge label={status.label} color={status.color} style="light-fill" />
              </div>
              <div data-part="definition-item">
                <span>{dgettext("dashboard_inference", "Profile")}</span>
                <a data-part="definition-link" href={~p"/ops/inference/profiles/#{@profile.id}"}>
                  {@profile.name}
                </a>
              </div>
              <div data-part="definition-item">
                <span>{dgettext("dashboard_inference", "Expires")}</span>
                <strong>{token_expiry_table_label(@token.expires_at)}</strong>
              </div>
              <div data-part="definition-item">
                <span>{dgettext("dashboard_inference", "Last used")}</span>
                <strong>{last_used_label(@token.last_used_at)}</strong>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card_section :if={@token.enabled} data-part="revoke-token-card-section">
          <div data-part="header">
            <span data-part="title">{dgettext("dashboard_inference", "Revoke token")}</span>
            <span data-part="subtitle">
              {dgettext(
                "dashboard_inference",
                "Repositories using this token will stop being able to use its profile."
              )}
            </span>
          </div>
          <div data-part="content">
            <.modal
              id="revoke-inference-token-modal"
              title={dgettext("dashboard_inference", "Revoke this token?")}
              description={dgettext("dashboard_inference", "This action cannot be undone.")}
              header_type="warning"
              header_size="large"
              on_dismiss="close_revoke_token"
            >
              <:trigger :let={attrs}>
                <.button
                  label={dgettext("dashboard_inference", "Revoke token")}
                  variant="destructive"
                  size="medium"
                  {attrs}
                />
              </:trigger>
              <.line_divider />
              <.alert
                status="warning"
                type="secondary"
                size="small"
                title={
                  dgettext(
                    "dashboard_inference",
                    "Revoking %{token} will immediately reject future requests using this token.",
                    token: @token.name
                  )
                }
              />
              <.line_divider />
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      type="button"
                      label={dgettext("dashboard_inference", "Cancel")}
                      variant="secondary"
                      size="medium"
                      phx-click="close_revoke_token"
                    />
                  </:action>
                  <:action>
                    <.button
                      type="button"
                      label={dgettext("dashboard_inference", "Revoke token")}
                      variant="destructive"
                      size="medium"
                      phx-click="revoke_token"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </div>
        </.card_section>
      </section>
    </Layouts.ops>
    """
  end

  defp assign_token(socket, id) do
    token = Inference.get_token_with_profile!(id)
    profile = token.model_binding

    socket
    |> assign(
      :page_title,
      dgettext("dashboard_inference", "%{token} · Inference · %{product}",
        token: token.name,
        product: socket.assigns.product_name
      )
    )
    |> assign(OpenGraph.assigns(open_graph(token, profile)))
    |> assign(:token, token)
    |> assign(:profile, profile)
    |> maybe_assign_usage()
  end

  defp assign_usage(%{assigns: %{token: token, usage_period: period}} = socket) do
    bucket = usage_period_bucket(socket.assigns.usage_preset, period)

    socket
    |> assign(:usage_bucket, bucket)
    |> assign(:usage_summary, Inference.usage_summary(token, period))
    |> assign(:usage_series, Inference.usage_series(token, period, bucket))
  end

  defp assign_usage(socket), do: socket

  defp maybe_assign_usage(%{assigns: %{usage_period: _period}} = socket), do: assign_usage(socket)
  defp maybe_assign_usage(socket), do: socket

  defp usage_period_patch(%Token{} = token, %URI{} = uri, "custom", %{
         "start" => start_at,
         "end" => end_at
       }) do
    query =
      uri.query
      |> Query.put("usage-date-range", "custom")
      |> Query.put("usage-start-date", start_at)
      |> Query.put("usage-end-date", end_at)
      |> Query.drop("usage-period")

    with_query(~p"/ops/inference/tokens/#{token.id}", query)
  end

  defp usage_period_patch(%Token{} = token, %URI{} = uri, preset, _value) do
    query =
      uri.query
      |> Query.put("usage-date-range", preset)
      |> Query.drop("usage-period")
      |> Query.drop("usage-start-date")
      |> Query.drop("usage-end-date")

    with_query(~p"/ops/inference/tokens/#{token.id}", query)
  end

  defp with_query(path, ""), do: path
  defp with_query(path, query), do: path <> "?" <> query

  defp record_token_audit(action, %ModelBinding{} = profile, %Token{} = token) do
    Audit.record(action, %{
      target_type: "inference_token",
      target_id: token.id,
      target_label: token.name,
      metadata: %{
        "profile_id" => profile.id,
        "profile_name" => profile.name,
        "path" => "/ops/inference/tokens/#{token.id}"
      }
    })
  end
end
