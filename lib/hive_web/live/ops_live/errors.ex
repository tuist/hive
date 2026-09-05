defmodule HiveWeb.OpsLive.Errors do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Audit
  alias Hive.Errors.Summaries
  alias Hive.Errors.SummarySettings
  alias Hive.Ops.Policy
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description: dgettext("dashboard_errors", "Configure scheduled Slack error summaries."),
      section_label: dgettext("dashboard_errors", "Ops"),
      highlights: [
        dgettext("dashboard_errors", "Runtime scheduling"),
        dgettext("dashboard_errors", "Slack delivery"),
        dgettext("dashboard_errors", "Special-attention issues")
      ],
      id: "ops-error-summaries",
      path: "/ops/errors",
      title: dgettext("dashboard_errors", "Error summaries")
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_errors", "Log in to manage error summaries."))
         |> redirect(to: ~p"/login?return_to=/ops/errors")}

      not Policy.authorize?(:error_summary_settings_manage, user, nil) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           dgettext("dashboard_errors", "Only instance admins can manage error summaries.")
         )
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok,
         socket
         |> assign(
           :page_title,
           dgettext("dashboard_errors", "Error summaries · %{product}",
             product: socket.assigns.product_name
           )
         )
         |> assign(OpenGraph.assigns(open_graph()))
         |> assign_settings(Summaries.settings())}
    end
  end

  @impl true
  def handle_event("validate", %{"error_summary_settings" => params}, socket) do
    changeset =
      socket.assigns.settings
      |> Summaries.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_settings_form(socket, changeset)}
  end

  def handle_event("save", %{"error_summary_settings" => params}, socket) do
    case Summaries.update_settings(socket.assigns.settings, params) do
      {:ok, settings} ->
        record_settings_audit(settings)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_errors", "Error summary settings updated."))
         |> assign_settings(settings)}

      {:error, changeset} ->
        {:noreply, assign_settings_form(socket, Map.put(changeset, :action, :validate))}
    end
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
      <section id="ops-error-summaries">
        <div data-part="page-header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_errors", "Error summaries")}</h1>
            <p>
              {dgettext(
                "dashboard_errors",
                "Send recurring summaries of unresolved errors to Slack and call out the issues that need special attention. Changes take effect without restarting Hive."
              )}
            </p>
          </div>
        </div>

        <.card
          icon="alert_circle"
          title={dgettext("dashboard_errors", "Slack summary")}
          data-part="settings-card"
        >
          <.card_section>
            <.form
              id="error-summary-settings-form"
              for={@settings_form}
              phx-change="validate"
              phx-submit="save"
              data-part="form"
            >
              <input
                type="hidden"
                name={@settings_form[:enabled].name}
                value="false"
              />
              <.toggle
                id="error-summary-enabled"
                field={@settings_form[:enabled]}
                label={dgettext("dashboard_errors", "Enable error summaries")}
                description={
                  dgettext(
                    "dashboard_errors",
                    "Generate a summary when the schedule matches and post it to Slack."
                  )
                }
              />
              <.text_input
                id="error-summary-schedule"
                field={@settings_form[:schedule]}
                label={dgettext("dashboard_errors", "Schedule")}
                sublabel={dgettext("dashboard_errors", "Coordinated Universal Time")}
                hint={
                  dgettext(
                    "dashboard_errors",
                    "Use a five-field Cron schedule, for example 0 9 * * * for every day at 09:00."
                  )
                }
                placeholder="0 9 * * *"
                required={true}
                show_required={true}
              />
              <.text_input
                id="error-summary-slack-channel"
                field={@settings_form[:slack_channel_id]}
                label={dgettext("dashboard_errors", "Slack channel identifier")}
                hint={
                  dgettext(
                    "dashboard_errors",
                    "Use the channel identifier from the connected Slack workspace, for example C0123456789."
                  )
                }
                placeholder="C0123456789"
                required={enabled?(@settings_form)}
                show_required={enabled?(@settings_form)}
              />
              <div data-part="form-actions">
                <.button
                  label={dgettext("dashboard_errors", "Save settings")}
                  variant="primary"
                  size="medium"
                  type="submit"
                />
              </div>
            </.form>
          </.card_section>
        </.card>
      </section>
    </Layouts.ops>
    """
  end

  defp assign_settings(socket, %SummarySettings{} = settings) do
    socket
    |> assign(:settings, settings)
    |> assign_settings_form(Summaries.change_settings(settings))
  end

  defp assign_settings_form(socket, changeset) do
    assign(socket, :settings_form, to_form(changeset, as: :error_summary_settings))
  end

  defp enabled?(form) do
    Phoenix.HTML.Form.normalize_value("checkbox", form[:enabled].value)
  end

  defp record_settings_audit(%SummarySettings{} = settings) do
    Audit.record("error_summary_settings.updated", %{
      target_type: "error_summary_settings",
      target_id: settings.id,
      target_label: dgettext("dashboard_errors", "Error summaries"),
      metadata: %{
        "enabled" => settings.enabled,
        "schedule" => settings.schedule,
        "slack_channel_id" => settings.slack_channel_id,
        "path" => "/ops/errors"
      }
    })
  end
end
