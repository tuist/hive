defmodule HiveWeb.AlertsLive.Index do
  @moduledoc false

  use HiveWeb, :live_view

  def slack_unfurl(_uri, _params), do: :skip

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/projects/#{id}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end

defmodule HiveWeb.AlertsLive.Rules do
  @moduledoc """
  Renders and manages a project's alert rules from the project page.

  The rule form keeps each value in component state because Noora dropdown
  content is portalled outside the surrounding form.
  """

  use Phoenix.LiveComponent
  use Gettext, backend: HiveWeb.Gettext
  use Noora

  alias Hive.Alerts
  alias Hive.Alerts.Rule
  alias Hive.Slack
  alias Hive.Slack.Installation

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :initialized_project_id, nil)}
  end

  @impl true
  def update(%{project: project} = assigns, socket) do
    socket = assign(socket, assigns)

    if socket.assigns.initialized_project_id == project.id do
      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(:initialized_project_id, project.id)
       |> assign(:installations, connected_installations())
       |> assign(:rules, Alerts.list_rules_for_project(project))
       |> assign(:editing_rule_id, nil)
       |> reset_form()}
    end
  end

  @impl true
  def handle_event("start_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_rule_id, nil)
     |> reset_form()}
  end

  def handle_event("start_edit", %{"id" => rule_id}, socket) do
    if socket.assigns.can_manage? do
      case find_rule(socket, rule_id) do
        %Rule{} = rule ->
          {:noreply,
           socket
           |> assign(:editing_rule_id, rule.id)
           |> assign(:rule_form, form_from_rule(rule))
           |> push_event("open-modal", %{id: "edit-alert-rule-modal"})}

        nil ->
          {:noreply, socket}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  def handle_event("update_form_name", %{"value" => value}, socket),
    do: {:noreply, socket |> put_form(:name, value) |> put_form(:error, nil)}

  def handle_event("update_form_trigger", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :trigger, to_atom(value, :new_issue_threshold))}

  def handle_event("update_form_threshold_count", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :threshold_count, parse_positive_int(value, 5))}

  def handle_event("update_form_threshold_window", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :threshold_window, parse_positive_int(value, 60))}

  def handle_event("update_form_tier", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :tier, to_atom(value, :attention))}

  def handle_event("update_form_min_level", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :min_level, to_atom_or_nil(value))}

  def handle_event("update_form_environment", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :environment, value)}

  def handle_event("update_form_cooldown", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :cooldown, parse_non_negative_int(value, 60))}

  def handle_event("update_form_destination", %{"value" => value}, socket) do
    destination = to_atom(value, :slack)
    {:noreply, socket |> put_form(:destination, destination) |> put_form(:error, nil)}
  end

  def handle_event("update_form_slack_installation", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :slack_installation_id, blank_to_nil(value))}

  def handle_event("update_form_slack_channel", %{"value" => value}, socket),
    do: {:noreply, socket |> put_form(:slack_channel, value) |> put_form(:error, nil)}

  def handle_event("update_form_slack_mention", %{"value" => value}, socket),
    do: {:noreply, put_form(socket, :slack_mention, to_atom(value, :none))}

  def handle_event("update_form_webhook_url", %{"value" => value}, socket),
    do: {:noreply, socket |> put_form(:webhook_url, value) |> put_form(:error, nil)}

  def handle_event("cancel_create", _params, socket) do
    {:noreply,
     socket
     |> reset_form()
     |> push_event("close-modal", %{id: "new-alert-rule-modal"})}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_rule_id, nil)
     |> reset_form()
     |> push_event("close-modal", %{id: "edit-alert-rule-modal"})}
  end

  def handle_event("create_rule", _params, socket) do
    if socket.assigns.can_manage? do
      create_rule(socket)
    else
      {:noreply, deny(socket)}
    end
  end

  def handle_event("update_rule", _params, socket) do
    if socket.assigns.can_manage? do
      update_rule(socket)
    else
      {:noreply, deny(socket)}
    end
  end

  def handle_event("toggle_enabled", %{"id" => rule_id}, socket) do
    if socket.assigns.can_manage? do
      case find_rule(socket, rule_id) do
        %Rule{} = rule ->
          {:ok, _rule} = Alerts.update_rule(rule, %{"enabled" => !rule.enabled})

          message =
            dgettext("dashboard_alerts", "Alert rule %{name} updated.", name: rule.name)

          {:noreply,
           socket
           |> notify_parent(:info, message)
           |> reload_rules()}

        nil ->
          {:noreply, socket}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  def handle_event("delete", %{"id" => rule_id}, socket) do
    if socket.assigns.can_manage? do
      case find_rule(socket, rule_id) do
        %Rule{} = rule ->
          {:ok, _rule} = Alerts.delete_rule(rule)

          {:noreply,
           socket
           |> notify_parent(:info, dgettext("dashboard_alerts", "Alert rule deleted."))
           |> reload_rules()}

        nil ->
          {:noreply, socket}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  defp create_rule(socket) do
    case Alerts.create_rule(socket.assigns.project, form_attrs(socket.assigns.rule_form)) do
      {:ok, rule} ->
        message =
          dgettext("dashboard_alerts", "Alert rule %{name} created.", name: rule.name)

        {:noreply,
         socket
         |> notify_parent(:info, message)
         |> reload_rules()
         |> reset_form()
         |> push_event("close-modal", %{id: "new-alert-rule-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_form(socket, :error, humanize_errors(changeset))}
    end
  end

  defp update_rule(socket) do
    case find_rule(socket, socket.assigns.editing_rule_id) do
      %Rule{} = rule ->
        case Alerts.update_rule(rule, form_attrs(socket.assigns.rule_form)) do
          {:ok, updated_rule} ->
            message =
              dgettext("dashboard_alerts", "Alert rule %{name} updated.", name: updated_rule.name)

            {:noreply,
             socket
             |> notify_parent(:info, message)
             |> reload_rules()
             |> assign(:editing_rule_id, nil)
             |> reset_form()
             |> push_event("close-modal", %{id: "edit-alert-rule-modal"})}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, put_form(socket, :error, humanize_errors(changeset))}
        end

      nil ->
        {:noreply, socket}
    end
  end

  defp find_rule(socket, rule_id),
    do: Enum.find(socket.assigns.rules, &(&1.id == rule_id))

  defp reload_rules(socket),
    do: assign(socket, :rules, Alerts.list_rules_for_project(socket.assigns.project))

  defp reset_form(socket) do
    assign(socket, :rule_form, %{
      name: "",
      trigger: :new_issue_threshold,
      threshold_count: 5,
      threshold_window: 60,
      tier: :attention,
      min_level: nil,
      environment: "",
      cooldown: 60,
      destination: :slack,
      slack_installation_id: default_installation_id(socket),
      slack_channel: "",
      slack_mention: :none,
      webhook_url: "",
      error: nil
    })
  end

  defp form_from_rule(%Rule{} = rule) do
    %{
      name: rule.name,
      trigger: rule.trigger,
      threshold_count: rule.threshold_event_count || 5,
      threshold_window: rule.threshold_window_minutes || 60,
      tier: rule.tier,
      min_level: rule.min_level,
      environment: rule.environment || "",
      cooldown: rule.cooldown_minutes,
      destination: rule.destination_type,
      slack_installation_id: rule.slack_installation_id,
      slack_channel: rule.slack_channel_id || "",
      slack_mention: rule.slack_mention || :none,
      webhook_url: rule.webhook_url || "",
      error: nil
    }
  end

  defp put_form(socket, key, value) do
    update(socket, :rule_form, &Map.put(&1, key, value))
  end

  defp default_installation_id(%{assigns: %{installations: [%Installation{id: id} | _]}}),
    do: id

  defp default_installation_id(_socket), do: nil

  defp form_attrs(form) do
    base = %{
      "name" => form.name,
      "trigger" => Atom.to_string(form.trigger),
      "tier" => Atom.to_string(form.tier),
      "min_level" => (form.min_level && Atom.to_string(form.min_level)) || nil,
      "environment" => nil_if_blank(form.environment),
      "cooldown_minutes" => form.cooldown,
      "destination_type" => Atom.to_string(form.destination),
      "threshold_event_count" => form.threshold_count,
      "threshold_window_minutes" => form.threshold_window
    }

    case form.destination do
      :slack ->
        Map.merge(base, %{
          "slack_installation_id" => form.slack_installation_id,
          "slack_channel_id" => form.slack_channel,
          "slack_mention" => Atom.to_string(form.slack_mention)
        })

      :webhook ->
        Map.put(base, "webhook_url", form.webhook_url)
    end
  end

  defp deny(socket) do
    notify_parent(
      socket,
      :error,
      dgettext("dashboard_alerts", "Only administrators can manage alert rules.")
    )
  end

  defp notify_parent(socket, kind, message) do
    send(self(), {:alert_rule_flash, kind, message})
    socket
  end

  defp connected_installations do
    Slack.list_installations()
    |> Enum.filter(&Installation.connected?/1)
  end

  defp to_atom(value, default) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> default
  end

  defp to_atom(_, default), do: default

  defp to_atom_or_nil(value) when value in [nil, ""], do: nil

  defp to_atom_or_nil(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp to_atom_or_nil(_), do: nil

  defp parse_positive_int(value, default) do
    case parse_int(value) do
      number when is_integer(number) and number > 0 -> number
      _other -> default
    end
  end

  defp parse_non_negative_int(value, default) do
    case parse_int(value) do
      number when is_integer(number) and number >= 0 -> number
      _other -> default
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _other -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp nil_if_blank(nil), do: nil

  defp nil_if_blank(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp nil_if_blank(value), do: value

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp humanize_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, result ->
        String.replace(result, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, errors} ->
      "#{humanize_field(field)}: #{Enum.join(errors, ", ")}"
    end)
  end

  defp humanize_field(field) do
    field
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="project-alerts" phx-target={"##{@id}"}>
      <.card title={dgettext("dashboard_projects", "Alerts")} icon="bell">
        <:actions :if={@can_manage?}>
          <.rule_modal
            mode={:create}
            form={@rule_form}
            installations={@installations}
            target={"##{@id}"}
          />
        </:actions>

        <.card_section data-part="alerts-card">
          <p data-part="alerts-intro">
            {dgettext(
              "dashboard_projects",
              "Send Slack messages or webhook deliveries when this project's error tracking flags something worth attention. Configure rules per project with a tier, filter, and destination."
            )}
          </p>

          <div data-part="resource-table">
            <.table
              id="alerts-rules-table"
              rows={@rules}
              row_key={fn rule -> "alert-rule-#{rule.id}" end}
            >
              <:col :let={rule} label={dgettext("dashboard_alerts", "Name")}>
                <.text_and_description_cell
                  label={rule.name}
                  description={trigger_description(rule)}
                />
              </:col>
              <:col :let={rule} label={dgettext("dashboard_alerts", "Tier")}>
                <div data-part="cell" data-type="badge">
                  <.badge
                    label={tier_label(rule.tier)}
                    color={tier_color(rule.tier)}
                    style="light-fill"
                    size="large"
                  />
                </div>
              </:col>
              <:col :let={rule} label={dgettext("dashboard_alerts", "Destination")}>
                <.text_cell label={destination_label(rule)} />
              </:col>
              <:col :let={rule} label={dgettext("dashboard_alerts", "Cooldown")}>
                <.text_cell label={cooldown_label(rule.cooldown_minutes)} />
              </:col>
              <:col :let={rule} label={dgettext("dashboard_alerts", "Enabled")}>
                <.text_cell label={if(rule.enabled, do: "Yes", else: "No")} />
              </:col>
              <:col :if={@can_manage?} :let={rule} label="">
                <.button_cell>
                  <:button>
                    <.dropdown id={"alert-rule-actions-#{rule.id}"} icon_only size="medium">
                      <:icon><.dots_vertical /></:icon>

                      <.dropdown_item
                        id={"edit-alert-rule-#{rule.id}"}
                        value="edit"
                        label={dgettext("dashboard_alerts", "Edit")}
                        on_click="start_edit"
                        phx-value-id={rule.id}
                        phx-target={"##{@id}"}
                      >
                        <:left_icon><.pencil /></:left_icon>
                      </.dropdown_item>
                      <.dropdown_item
                        id={"toggle-alert-rule-#{rule.id}"}
                        value={if(rule.enabled, do: "disable", else: "enable")}
                        label={
                          if(rule.enabled,
                            do: dgettext("dashboard_alerts", "Disable"),
                            else: dgettext("dashboard_alerts", "Enable")
                          )
                        }
                        on_click="toggle_enabled"
                        phx-value-id={rule.id}
                        phx-target={"##{@id}"}
                      >
                        <:left_icon>
                          <.circle_x :if={rule.enabled} />
                          <.circle_check :if={!rule.enabled} />
                        </:left_icon>
                      </.dropdown_item>
                      <.dropdown_item
                        id={"delete-alert-rule-#{rule.id}"}
                        value="delete"
                        label={dgettext("dashboard_alerts", "Delete")}
                        on_click="delete"
                        phx-value-id={rule.id}
                        phx-target={"##{@id}"}
                        data-confirm={
                          dgettext("dashboard_alerts", "Delete alert rule %{name}?", name: rule.name)
                        }
                      >
                        <:left_icon><.trash /></:left_icon>
                      </.dropdown_item>
                    </.dropdown>
                  </:button>
                </.button_cell>
              </:col>
              <:empty_state>
                <.table_empty_state
                  icon="bell"
                  title={dgettext("dashboard_alerts", "No alert rules yet")}
                  subtitle={
                    dgettext(
                      "dashboard_alerts",
                      "Create a rule to get notified in Slack or via webhook when errors need attention."
                    )
                  }
                />
              </:empty_state>
            </.table>
          </div>
        </.card_section>
      </.card>

      <.rule_modal
        :if={@editing_rule_id}
        mode={:edit}
        form={@rule_form}
        installations={@installations}
        target={"##{@id}"}
      />
    </div>
    """
  end

  attr :mode, :atom, values: [:create, :edit], required: true
  attr :form, :map, required: true
  attr :installations, :list, required: true
  attr :target, :any, required: true

  defp rule_modal(assigns) do
    assigns = assign(assigns, modal_options(assigns.mode))

    ~H"""
    <.modal id={@modal_id} title={@title} description={@description} phx-target={@target}>
      <:trigger :let={attrs}>
        <.button
          :if={@mode == :create}
          id="new-alert-rule"
          label={dgettext("dashboard_alerts", "New alert rule")}
          size="medium"
          variant="primary"
          type="button"
          phx-click="start_create"
          phx-target={@target}
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
        <button :if={@mode == :edit} type="button" hidden {attrs}></button>
      </:trigger>

      <div data-part="rule-form">
        <.alert
          :if={@form.error}
          status="error"
          type="secondary"
          size="small"
          title={@form.error}
        />

        <.text_input
          id={"#{@modal_id}-name"}
          name="name"
          type="basic"
          label={dgettext("dashboard_alerts", "Name")}
          value={@form.name}
          placeholder={dgettext("dashboard_alerts", "e.g. Production regressions")}
          phx-keyup="update_form_name"
          phx-target={@target}
          phx-debounce="200"
        />

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Trigger")}</span>
          <.dropdown id={"#{@modal_id}-trigger"} label={trigger_label(@form.trigger)}>
            <.dropdown_item
              :for={trigger <- [:new_issue_threshold, :regression]}
              value={Atom.to_string(trigger)}
              label={trigger_label(trigger)}
              phx-click="update_form_trigger"
              phx-value-value={Atom.to_string(trigger)}
              phx-target={@target}
              data-selected={trigger == @form.trigger}
            />
          </.dropdown>
        </div>

        <div :if={@form.trigger == :new_issue_threshold} data-part="threshold-row">
          <.text_input
            id={"#{@modal_id}-threshold-count"}
            name="threshold_event_count"
            type="basic"
            label={dgettext("dashboard_alerts", "Events")}
            value={to_string(@form.threshold_count)}
            phx-keyup="update_form_threshold_count"
            phx-target={@target}
            phx-debounce="200"
          />
          <.text_input
            id={"#{@modal_id}-threshold-window"}
            name="threshold_window_minutes"
            type="basic"
            label={dgettext("dashboard_alerts", "Window (minutes)")}
            value={to_string(@form.threshold_window)}
            phx-keyup="update_form_threshold_window"
            phx-target={@target}
            phx-debounce="200"
          />
        </div>

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Tier")}</span>
          <.dropdown id={"#{@modal_id}-tier"} label={tier_label(@form.tier)}>
            <.dropdown_item
              :for={tier <- [:attention, :incident]}
              value={Atom.to_string(tier)}
              label={tier_label(tier)}
              phx-click="update_form_tier"
              phx-value-value={Atom.to_string(tier)}
              phx-target={@target}
              data-selected={tier == @form.tier}
            />
          </.dropdown>
        </div>

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Minimum level")}</span>
          <.dropdown id={"#{@modal_id}-min-level"} label={level_label(@form.min_level)}>
            <.dropdown_item
              value=""
              label={level_label(nil)}
              phx-click="update_form_min_level"
              phx-value-value=""
              phx-target={@target}
              data-selected={is_nil(@form.min_level)}
            />
            <.dropdown_item
              :for={level <- [:warning, :error, :fatal]}
              value={Atom.to_string(level)}
              label={level_label(level)}
              phx-click="update_form_min_level"
              phx-value-value={Atom.to_string(level)}
              phx-target={@target}
              data-selected={level == @form.min_level}
            />
          </.dropdown>
        </div>

        <.text_input
          id={"#{@modal_id}-environment"}
          name="environment"
          type="basic"
          label={dgettext("dashboard_alerts", "Environment (optional)")}
          value={@form.environment}
          placeholder="production"
          phx-keyup="update_form_environment"
          phx-target={@target}
          phx-debounce="200"
        />

        <.text_input
          id={"#{@modal_id}-cooldown"}
          name="cooldown_minutes"
          type="basic"
          label={dgettext("dashboard_alerts", "Cooldown (minutes)")}
          value={to_string(@form.cooldown)}
          phx-keyup="update_form_cooldown"
          phx-target={@target}
          phx-debounce="200"
        />

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Destination")}</span>
          <.dropdown
            id={"#{@modal_id}-destination"}
            label={destination_type_label(@form.destination)}
          >
            <.dropdown_item
              :for={destination <- [:slack, :webhook]}
              value={Atom.to_string(destination)}
              label={destination_type_label(destination)}
              phx-click="update_form_destination"
              phx-value-value={Atom.to_string(destination)}
              phx-target={@target}
              data-selected={destination == @form.destination}
            />
          </.dropdown>
        </div>

        <div :if={@form.destination == :slack} data-part="destination-fields">
          <div data-part="select-field">
            <span>{dgettext("dashboard_alerts", "Slack workspace")}</span>
            <.dropdown
              id={"#{@modal_id}-installation"}
              label={installation_label(@installations, @form.slack_installation_id)}
            >
              <.dropdown_item
                :for={installation <- @installations}
                value={installation.id}
                label={installation.team_name || installation.team_id}
                phx-click="update_form_slack_installation"
                phx-value-value={installation.id}
                phx-target={@target}
                data-selected={installation.id == @form.slack_installation_id}
              />
            </.dropdown>
          </div>

          <.text_input
            id={"#{@modal_id}-channel"}
            name="slack_channel_id"
            type="basic"
            label={dgettext("dashboard_alerts", "Slack channel identifier")}
            value={@form.slack_channel}
            placeholder="C0123456789"
            phx-keyup="update_form_slack_channel"
            phx-target={@target}
            phx-debounce="200"
          />

          <div data-part="select-field">
            <span>{dgettext("dashboard_alerts", "Mention")}</span>
            <.dropdown id={"#{@modal_id}-mention"} label={mention_label(@form.slack_mention)}>
              <.dropdown_item
                :for={mention <- [:none, :here, :channel]}
                value={Atom.to_string(mention)}
                label={mention_label(mention)}
                phx-click="update_form_slack_mention"
                phx-value-value={Atom.to_string(mention)}
                phx-target={@target}
                data-selected={mention == @form.slack_mention}
              />
            </.dropdown>
          </div>
        </div>

        <div :if={@form.destination == :webhook} data-part="destination-fields">
          <.text_input
            id={"#{@modal_id}-webhook-url"}
            name="webhook_url"
            type="basic"
            label={dgettext("dashboard_alerts", "Webhook address")}
            value={@form.webhook_url}
            placeholder="https://example.com/hooks/hive"
            phx-keyup="update_form_webhook_url"
            phx-target={@target}
            phx-debounce="200"
          />
          <p data-part="webhook-help">
            {dgettext(
              "dashboard_alerts",
              "Hive sends a signed request payload. A signing secret is minted on save; store it and verify the X-Hive-Signature header."
            )}
          </p>
        </div>
      </div>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label={dgettext("dashboard_alerts", "Cancel")}
              variant="secondary"
              size="medium"
              type="button"
              phx-click={@cancel_event}
              phx-target={@target}
            />
          </:action>
          <:action>
            <.button
              id={@save_button_id}
              label={@save_label}
              variant="primary"
              size="medium"
              type="button"
              phx-click={@save_event}
              phx-target={@target}
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp modal_options(:create) do
    %{
      modal_id: "new-alert-rule-modal",
      title: dgettext("dashboard_alerts", "New alert rule"),
      description:
        dgettext(
          "dashboard_alerts",
          "Pick a trigger, an urgency tier, and where the message should go."
        ),
      cancel_event: "cancel_create",
      save_event: "create_rule",
      save_button_id: "create-alert-rule",
      save_label: dgettext("dashboard_alerts", "Create alert rule")
    }
  end

  defp modal_options(:edit) do
    %{
      modal_id: "edit-alert-rule-modal",
      title: dgettext("dashboard_alerts", "Edit alert rule"),
      description:
        dgettext(
          "dashboard_alerts",
          "Update when this rule fires, its urgency, or where the message should go."
        ),
      cancel_event: "cancel_edit",
      save_event: "update_rule",
      save_button_id: "save-alert-rule",
      save_label: dgettext("dashboard_alerts", "Save changes")
    }
  end

  defp trigger_label(:regression),
    do: dgettext("dashboard_alerts", "Regression (resolved issue reopens)")

  defp trigger_label(_new_issue_threshold),
    do: dgettext("dashboard_alerts", "New issue crosses threshold")

  defp tier_label(:incident), do: dgettext("dashboard_alerts", "Incident")
  defp tier_label(_attention), do: dgettext("dashboard_alerts", "Attention")

  defp tier_color(:incident), do: "destructive"
  defp tier_color(_attention), do: "warning"

  defp level_label(nil), do: dgettext("dashboard_alerts", "Any level")
  defp level_label(level) when is_atom(level), do: Atom.to_string(level)

  defp mention_label(:here), do: "@here"
  defp mention_label(:channel), do: "@channel"
  defp mention_label(_none), do: dgettext("dashboard_alerts", "No mention")

  defp destination_type_label(:webhook),
    do: dgettext("dashboard_alerts", "Secure webhook")

  defp destination_type_label(_slack), do: dgettext("dashboard_alerts", "Slack")

  defp installation_label([], _id), do: dgettext("dashboard_alerts", "No connected workspace")

  defp installation_label(installations, id) do
    case Enum.find(installations, &(&1.id == id)) do
      nil -> dgettext("dashboard_alerts", "Choose workspace")
      installation -> installation.team_name || installation.team_id
    end
  end

  defp destination_label(%Rule{destination_type: :webhook, webhook_url: url})
       when is_binary(url) and url != "" do
    host =
      case URI.parse(url) do
        %URI{host: host} when is_binary(host) -> host
        _other -> url
      end

    "Webhook · #{host}"
  end

  defp destination_label(%Rule{
         destination_type: :slack,
         slack_installation: %{team_name: name},
         slack_channel_id: channel
       })
       when is_binary(name) and is_binary(channel),
       do: "Slack · #{name} · #{channel}"

  defp destination_label(%Rule{destination_type: :slack, slack_channel_id: channel})
       when is_binary(channel),
       do: "Slack · #{channel}"

  defp destination_label(_rule), do: dgettext("dashboard_alerts", "No destination")

  defp trigger_description(%Rule{trigger: :regression}),
    do: dgettext("dashboard_alerts", "Fires when a resolved issue comes back")

  defp trigger_description(%Rule{
         trigger: :new_issue_threshold,
         threshold_event_count: count,
         threshold_window_minutes: window
       }) do
    dgettext(
      "dashboard_alerts",
      "Fires when a new issue reaches %{count} events in %{window} minutes",
      count: count,
      window: window
    )
  end

  defp trigger_description(_rule), do: ""

  defp cooldown_label(0), do: dgettext("dashboard_alerts", "no cooldown")

  defp cooldown_label(minutes) when is_integer(minutes),
    do: dgettext("dashboard_alerts", "%{minutes} min", minutes: minutes)
end
