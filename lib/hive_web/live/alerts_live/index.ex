defmodule HiveWeb.AlertsLive.Index do
  @moduledoc """
  Lists a project's alert rules and lets admins create, enable, disable,
  or delete them.

  Rule creation lives in a modal on this page. Form state is kept in
  socket assigns and each input reports back via a `phx-keyup` /
  `phx-click` event, mirroring `../tuist/server/lib/tuist_web/live/webhooks_live.ex`.
  This sidesteps a Noora Select portal quirk where the select's value
  can be dropped from `phx-submit` params inside a modal.
  """

  use HiveWeb, :live_view
  use Noora

  alias Hive.Alerts
  alias Hive.Alerts.Policy
  alias Hive.Alerts.Rule
  alias Hive.Auth
  alias Hive.Projects
  alias Hive.Slack
  alias Hive.Slack.Installation
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def slack_unfurl(_uri, _params), do: :skip

  def open_graph(project) do
    %{
      description:
        dgettext(
          "dashboard_alerts",
          "Alert rules for %{project}: when to notify, and where.",
          project: project.name
        ),
      section_label: dgettext("dashboard_alerts", "Alerts"),
      highlights: [project.name],
      id: "project-#{project.id}-alerts",
      path: "/projects/#{project.id}/alerts",
      title: dgettext("dashboard_alerts", "Alerts · %{project}", project: project.name)
    }
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]

    case Projects.fetch_visible_project(id, user) do
      {:ok, project} ->
        if Policy.authorize?(:alert_rule_read, user, nil) do
          {:ok,
           socket
           |> assign(:project, project)
           |> assign(:can_manage?, Auth.admin?(user))
           |> assign(:installations, connected_installations())
           |> assign(:rules, Alerts.list_rules_for_project(project))
           |> assign(
             :page_title,
             dgettext("dashboard_alerts", "Alerts · %{project} · %{product}",
               project: project.name,
               product: socket.assigns.product_name
             )
           )
           |> assign(OpenGraph.assigns(open_graph(project)))
           |> reset_create_form()}
        else
          {:ok,
           socket
           |> put_flash(:error, dgettext("dashboard_alerts", "Alerts require an org account."))
           |> push_navigate(to: ~p"/projects/#{project.id}")}
        end

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("dashboard_alerts", "Project not found."))
         |> push_navigate(to: ~p"/projects")}
    end
  end

  ## Form field events — each input owns one, so the modal's portal cannot
  ## drop values on submit.

  @impl true
  def handle_event("update_form_name", %{"value" => value}, socket),
    do: {:noreply, socket |> assign(:form_name, value) |> assign(:form_error, nil)}

  def handle_event("update_form_trigger", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_trigger, to_atom(value, :new_issue_threshold))}

  def handle_event("update_form_threshold_count", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_threshold_count, parse_positive_int(value, 5))}

  def handle_event("update_form_threshold_window", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_threshold_window, parse_positive_int(value, 60))}

  def handle_event("update_form_tier", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_tier, to_atom(value, :attention))}

  def handle_event("update_form_min_level", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_min_level, to_atom_or_nil(value))}

  def handle_event("update_form_environment", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_environment, value)}

  def handle_event("update_form_cooldown", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_cooldown, parse_non_negative_int(value, 60))}

  def handle_event("update_form_destination", %{"value" => value}, socket) do
    destination = to_atom(value, :slack)
    {:noreply, socket |> assign(:form_destination, destination) |> assign(:form_error, nil)}
  end

  def handle_event("update_form_slack_installation", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_slack_installation_id, blank_to_nil(value))}

  def handle_event("update_form_slack_channel", %{"value" => value}, socket),
    do: {:noreply, socket |> assign(:form_slack_channel, value) |> assign(:form_error, nil)}

  def handle_event("update_form_slack_mention", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :form_slack_mention, to_atom(value, :none))}

  def handle_event("update_form_webhook_url", %{"value" => value}, socket),
    do: {:noreply, socket |> assign(:form_webhook_url, value) |> assign(:form_error, nil)}

  def handle_event("create_modal_open_change", %{"open" => false}, socket),
    do: {:noreply, reset_create_form(socket)}

  def handle_event("create_modal_open_change", _params, socket),
    do: {:noreply, socket}

  def handle_event("cancel_create", _params, socket) do
    {:noreply,
     socket
     |> reset_create_form()
     |> push_event("close-modal", %{id: "new-alert-rule-modal"})}
  end

  def handle_event("create_rule", _params, socket) do
    if socket.assigns.can_manage? do
      do_create_rule(socket)
    else
      {:noreply, deny(socket)}
    end
  end

  def handle_event("toggle_enabled", %{"id" => rule_id}, socket) do
    if socket.assigns.can_manage? do
      case Enum.find(socket.assigns.rules, &(&1.id == rule_id)) do
        %Rule{} = rule ->
          {:ok, _} = Alerts.update_rule(rule, %{"enabled" => !rule.enabled})

          {:noreply,
           socket
           |> put_flash(
             :info,
             dgettext("dashboard_alerts", "Alert rule %{name} updated.", name: rule.name)
           )
           |> reload_rules()}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  def handle_event("delete", %{"id" => rule_id}, socket) do
    if socket.assigns.can_manage? do
      case Enum.find(socket.assigns.rules, &(&1.id == rule_id)) do
        %Rule{} = rule ->
          {:ok, _} = Alerts.delete_rule(rule)

          {:noreply,
           socket
           |> put_flash(:info, dgettext("dashboard_alerts", "Alert rule deleted."))
           |> reload_rules()}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, deny(socket)}
    end
  end

  defp do_create_rule(socket) do
    case Alerts.create_rule(socket.assigns.project, form_attrs(socket.assigns)) do
      {:ok, rule} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext("dashboard_alerts", "Alert rule %{name} created.", name: rule.name)
         )
         |> reload_rules()
         |> reset_create_form()
         |> push_event("close-modal", %{id: "new-alert-rule-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form_error, humanize_errors(changeset))}
    end
  end

  defp reload_rules(socket),
    do: assign(socket, :rules, Alerts.list_rules_for_project(socket.assigns.project))

  defp reset_create_form(socket) do
    socket
    |> assign(:form_name, "")
    |> assign(:form_trigger, :new_issue_threshold)
    |> assign(:form_threshold_count, 5)
    |> assign(:form_threshold_window, 60)
    |> assign(:form_tier, :attention)
    |> assign(:form_min_level, nil)
    |> assign(:form_environment, "")
    |> assign(:form_cooldown, 60)
    |> assign(:form_destination, :slack)
    |> assign(:form_slack_installation_id, default_installation_id(socket))
    |> assign(:form_slack_channel, "")
    |> assign(:form_slack_mention, :none)
    |> assign(:form_webhook_url, "")
    |> assign(:form_error, nil)
  end

  defp default_installation_id(%{assigns: %{installations: [%Installation{id: id} | _]}}), do: id
  defp default_installation_id(_socket), do: nil

  defp form_attrs(assigns) do
    base = %{
      "name" => assigns.form_name,
      "trigger" => Atom.to_string(assigns.form_trigger),
      "tier" => Atom.to_string(assigns.form_tier),
      "min_level" => (assigns.form_min_level && Atom.to_string(assigns.form_min_level)) || nil,
      "environment" => nil_if_blank(assigns.form_environment),
      "cooldown_minutes" => assigns.form_cooldown,
      "destination_type" => Atom.to_string(assigns.form_destination),
      "threshold_event_count" => assigns.form_threshold_count,
      "threshold_window_minutes" => assigns.form_threshold_window
    }

    case assigns.form_destination do
      :slack ->
        Map.merge(base, %{
          "slack_installation_id" => assigns.form_slack_installation_id,
          "slack_channel_id" => assigns.form_slack_channel,
          "slack_mention" => Atom.to_string(assigns.form_slack_mention)
        })

      :webhook ->
        Map.put(base, "webhook_url", assigns.form_webhook_url)
    end
  end

  defp deny(socket) do
    put_flash(
      socket,
      :error,
      dgettext("dashboard_alerts", "Only administrators can manage alert rules.")
    )
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
      n when is_integer(n) and n > 0 -> n
      _ -> default
    end
  end

  defp parse_non_negative_int(value, default) do
    case parse_int(value) do
      n when is_integer(n) and n >= 0 -> n
      _ -> default
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp nil_if_blank(nil), do: nil

  defp nil_if_blank(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp nil_if_blank(value), do: value

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp humanize_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(". ", fn {field, errs} ->
      "#{humanize_field(field)}: #{Enum.join(errs, ", ")}"
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
    >
      <section id="project-alerts">
        <div data-part="header">
          <div data-part="title-group">
            <h1>{dgettext("dashboard_alerts", "Alerts · %{project}", project: @project.name)}</h1>
            <p>
              {dgettext(
                "dashboard_alerts",
                "Rules watch this project's error tracking. Attention rules ping a channel; incident rules page it."
              )}
            </p>
          </div>
          <div data-part="header-actions">
            <.new_rule_modal
              :if={@can_manage?}
              installations={@installations}
              form_name={@form_name}
              form_trigger={@form_trigger}
              form_threshold_count={@form_threshold_count}
              form_threshold_window={@form_threshold_window}
              form_tier={@form_tier}
              form_min_level={@form_min_level}
              form_environment={@form_environment}
              form_cooldown={@form_cooldown}
              form_destination={@form_destination}
              form_slack_installation_id={@form_slack_installation_id}
              form_slack_channel={@form_slack_channel}
              form_slack_mention={@form_slack_mention}
              form_webhook_url={@form_webhook_url}
              form_error={@form_error}
            />
          </div>
        </div>

        <.card title={dgettext("dashboard_alerts", "Rules")} icon="bell">
          <.card_section>
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
                      <.button
                        label={
                          if(rule.enabled,
                            do: dgettext("dashboard_alerts", "Disable"),
                            else: dgettext("dashboard_alerts", "Enable")
                          )
                        }
                        size="medium"
                        variant="secondary"
                        phx-click="toggle_enabled"
                        phx-value-id={rule.id}
                      />
                    </:button>
                    <:button>
                      <.button
                        label={dgettext("dashboard_alerts", "Delete rule")}
                        size="large"
                        variant="secondary"
                        icon_only={true}
                        phx-click="delete"
                        phx-value-id={rule.id}
                        data-confirm={
                          dgettext("dashboard_alerts", "Delete alert rule %{name}?",
                            name: rule.name
                          )
                        }
                        title={dgettext("dashboard_alerts", "Delete rule")}
                        aria-label={dgettext("dashboard_alerts", "Delete rule")}
                      >
                        <.trash />
                      </.button>
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
      </section>
    </Layouts.dashboard>
    """
  end

  ## Modal shell

  attr :installations, :list, required: true
  attr :form_name, :string, required: true
  attr :form_trigger, :atom, required: true
  attr :form_threshold_count, :integer, required: true
  attr :form_threshold_window, :integer, required: true
  attr :form_tier, :atom, required: true
  attr :form_min_level, :any, required: true
  attr :form_environment, :string, required: true
  attr :form_cooldown, :integer, required: true
  attr :form_destination, :atom, required: true
  attr :form_slack_installation_id, :any, required: true
  attr :form_slack_channel, :string, required: true
  attr :form_slack_mention, :atom, required: true
  attr :form_webhook_url, :string, required: true
  attr :form_error, :any, required: true

  defp new_rule_modal(assigns) do
    ~H"""
    <.modal
      id="new-alert-rule-modal"
      title={dgettext("dashboard_alerts", "New alert rule")}
      description={dgettext("dashboard_alerts", "Pick a trigger, an urgency tier, and where the message should go.")}
      on_dismiss="cancel_create"
      on_open_change="create_modal_open_change"
    >
      <:trigger :let={attrs}>
        <.button
          label={dgettext("dashboard_alerts", "New alert rule")}
          size="medium"
          variant="primary"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>

      <div data-part="rule-form">
        <.alert
          :if={@form_error}
          status="error"
          type="secondary"
          size="small"
          title={@form_error}
        />

        <.text_input
          id="alert-rule-name"
          name="name"
          type="basic"
          label={dgettext("dashboard_alerts", "Name")}
          value={@form_name}
          placeholder={dgettext("dashboard_alerts", "e.g. Production regressions")}
          phx-keyup="update_form_name"
          phx-debounce="200"
        />

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Trigger")}</span>
          <.dropdown id="alert-rule-trigger" label={trigger_label(@form_trigger)}>
            <.dropdown_item
              :for={trigger <- [:new_issue_threshold, :regression]}
              value={Atom.to_string(trigger)}
              label={trigger_label(trigger)}
              phx-click="update_form_trigger"
              phx-value-value={Atom.to_string(trigger)}
              data-selected={trigger == @form_trigger}
            />
          </.dropdown>
        </div>

        <div :if={@form_trigger == :new_issue_threshold} data-part="threshold-row">
          <.text_input
            id="alert-rule-threshold-count"
            name="threshold_event_count"
            type="basic"
            label={dgettext("dashboard_alerts", "Events")}
            value={to_string(@form_threshold_count)}
            phx-keyup="update_form_threshold_count"
            phx-debounce="200"
          />
          <.text_input
            id="alert-rule-threshold-window"
            name="threshold_window_minutes"
            type="basic"
            label={dgettext("dashboard_alerts", "Window (minutes)")}
            value={to_string(@form_threshold_window)}
            phx-keyup="update_form_threshold_window"
            phx-debounce="200"
          />
        </div>

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Tier")}</span>
          <.dropdown id="alert-rule-tier" label={tier_label(@form_tier)}>
            <.dropdown_item
              :for={tier <- [:attention, :incident]}
              value={Atom.to_string(tier)}
              label={tier_label(tier)}
              phx-click="update_form_tier"
              phx-value-value={Atom.to_string(tier)}
              data-selected={tier == @form_tier}
            />
          </.dropdown>
        </div>

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Minimum level")}</span>
          <.dropdown id="alert-rule-min-level" label={level_label(@form_min_level)}>
            <.dropdown_item
              value=""
              label={level_label(nil)}
              phx-click="update_form_min_level"
              phx-value-value=""
              data-selected={is_nil(@form_min_level)}
            />
            <.dropdown_item
              :for={level <- [:warning, :error, :fatal]}
              value={Atom.to_string(level)}
              label={level_label(level)}
              phx-click="update_form_min_level"
              phx-value-value={Atom.to_string(level)}
              data-selected={level == @form_min_level}
            />
          </.dropdown>
        </div>

        <.text_input
          id="alert-rule-environment"
          name="environment"
          type="basic"
          label={dgettext("dashboard_alerts", "Environment (optional)")}
          value={@form_environment}
          placeholder="production"
          phx-keyup="update_form_environment"
          phx-debounce="200"
        />

        <.text_input
          id="alert-rule-cooldown"
          name="cooldown_minutes"
          type="basic"
          label={dgettext("dashboard_alerts", "Cooldown (minutes)")}
          value={to_string(@form_cooldown)}
          phx-keyup="update_form_cooldown"
          phx-debounce="200"
        />

        <div data-part="select-field">
          <span>{dgettext("dashboard_alerts", "Destination")}</span>
          <.dropdown id="alert-rule-destination" label={destination_type_label(@form_destination)}>
            <.dropdown_item
              :for={destination <- [:slack, :webhook]}
              value={Atom.to_string(destination)}
              label={destination_type_label(destination)}
              phx-click="update_form_destination"
              phx-value-value={Atom.to_string(destination)}
              data-selected={destination == @form_destination}
            />
          </.dropdown>
        </div>

        <div :if={@form_destination == :slack} data-part="destination-fields">
          <div data-part="select-field">
            <span>{dgettext("dashboard_alerts", "Slack workspace")}</span>
            <.dropdown
              id="alert-rule-installation"
              label={installation_label(@installations, @form_slack_installation_id)}
            >
              <.dropdown_item
                :for={installation <- @installations}
                value={installation.id}
                label={installation.team_name || installation.team_id}
                phx-click="update_form_slack_installation"
                phx-value-value={installation.id}
                data-selected={installation.id == @form_slack_installation_id}
              />
            </.dropdown>
          </div>

          <.text_input
            id="alert-rule-channel"
            name="slack_channel_id"
            type="basic"
            label={dgettext("dashboard_alerts", "Slack channel ID")}
            value={@form_slack_channel}
            placeholder="C0123456789"
            phx-keyup="update_form_slack_channel"
            phx-debounce="200"
          />

          <div data-part="select-field">
            <span>{dgettext("dashboard_alerts", "Mention")}</span>
            <.dropdown id="alert-rule-mention" label={mention_label(@form_slack_mention)}>
              <.dropdown_item
                :for={mention <- [:none, :here, :channel]}
                value={Atom.to_string(mention)}
                label={mention_label(mention)}
                phx-click="update_form_slack_mention"
                phx-value-value={Atom.to_string(mention)}
                data-selected={mention == @form_slack_mention}
              />
            </.dropdown>
          </div>
        </div>

        <div :if={@form_destination == :webhook} data-part="destination-fields">
          <.text_input
            id="alert-rule-webhook-url"
            name="webhook_url"
            type="basic"
            label={dgettext("dashboard_alerts", "Webhook URL")}
            value={@form_webhook_url}
            placeholder="https://example.com/hooks/hive"
            phx-keyup="update_form_webhook_url"
            phx-debounce="200"
          />
          <p data-part="webhook-help">
            {dgettext(
              "dashboard_alerts",
              "Hive POSTs a signed JSON envelope. A signing secret is minted on save; store it and verify the X-Hive-Signature header."
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
              phx-click="cancel_create"
            />
          </:action>
          <:action>
            <.button
              label={dgettext("dashboard_alerts", "Create alert rule")}
              variant="primary"
              size="medium"
              phx-click="create_rule"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  ## Label helpers

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

  defp destination_type_label(:webhook), do: dgettext("dashboard_alerts", "Webhook (HTTPS)")
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
        %URI{host: h} when is_binary(h) -> h
        _ -> url
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
