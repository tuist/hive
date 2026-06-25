defmodule HiveWeb.OpsLive.InferenceProfile do
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

  def open_graph(%ModelBinding{} = profile) do
    %{
      description: "Manage the #{profile.name} inference profile and its repository tokens.",
      section_label: "Ops",
      highlights: ["Profile configuration", "Repository tokens", "Upstream model routing"],
      id: "ops-inference-profile",
      path: "/ops/inference/profiles/#{profile.id}",
      title: profile.name
    }
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Log in to manage inference profiles.")
         |> redirect(to: ~p"/login?#{[return_to: "/ops/inference/profiles/#{id}"]}")}

      not Policy.authorize?(:inference_profile_manage, user, nil) ->
        {:ok,
         socket
         |> put_flash(:error, "Only instance admins can manage inference profiles.")
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok,
         socket
         |> assign(:generated_token, nil)
         |> assign_profile(id)}
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
       to: usage_period_patch(socket.assigns.profile, socket.assigns.uri, preset, value)
     )}
  end

  def handle_event("validate_profile", %{"profile" => params}, socket) do
    changeset =
      socket.assigns.profile
      |> Inference.change_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_profile_form(socket, changeset)}
  end

  def handle_event("profile_provider_changed", params, socket) do
    params =
      socket.assigns.profile_form
      |> form_params()
      |> Map.put("upstream_provider", selected_value(params))

    {:noreply,
     assign_profile_form(socket, Inference.change_profile(socket.assigns.profile, params))}
  end

  def handle_event("update_profile", %{"profile" => params}, socket) do
    profile = socket.assigns.profile

    case Inference.update_profile(profile, params) do
      {:ok, profile} ->
        record_profile_audit(:"inference_profile.updated", profile)

        {:noreply,
         socket
         |> put_flash(:info, "Profile updated.")
         |> assign(:generated_token, nil)
         |> assign_profile(profile.id)
         |> push_event("close-modal", %{id: "edit-inference-profile-modal"})}

      {:error, changeset} ->
        {:noreply, assign_profile_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("toggle_profile", _params, socket) do
    profile = socket.assigns.profile

    case Inference.update_profile(profile, %{"enabled" => !profile.enabled}) do
      {:ok, profile} ->
        record_profile_audit(:"inference_profile.updated", profile)

        {:noreply,
         socket
         |> put_flash(
           :info,
           if(profile.enabled, do: "Profile enabled.", else: "Profile disabled.")
         )
         |> assign(:generated_token, nil)
         |> assign_profile(profile.id)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update profile.")}
    end
  end

  def handle_event("create_token", %{"token" => params}, socket) do
    profile = socket.assigns.profile

    case Inference.create_profile_token(profile, params) do
      {:ok, {token, token_value}} ->
        record_token_audit(:"inference_token.created", profile, token)

        generated_token = %{
          token_name: token.name,
          value: token_value
        }

        {:noreply,
         socket
         |> put_flash(:info, "Token created.")
         |> assign_profile(profile.id)
         |> assign(:generated_token, generated_token)
         |> push_event("close-modal", %{id: "new-inference-token-modal"})}

      {:error, changeset} ->
        {:noreply, assign_token_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("open_edit_profile", _params, socket) do
    {:noreply,
     socket
     |> assign_profile_form(Inference.change_profile(socket.assigns.profile))
     |> push_event("open-modal", %{id: "edit-inference-profile-modal"})}
  end

  def handle_event("open_new_token", _params, socket) do
    {:noreply,
     socket
     |> assign_token_form(Inference.change_token(socket.assigns.profile))
     |> push_event("open-modal", %{id: "new-inference-token-modal"})}
  end

  def handle_event("dismiss_generated_token", _params, socket) do
    {:noreply, assign(socket, :generated_token, nil)}
  end

  def handle_event("close_edit_profile", _params, socket) do
    {:noreply,
     socket
     |> assign_profile_form(Inference.change_profile(socket.assigns.profile))
     |> push_event("close-modal", %{id: "edit-inference-profile-modal"})}
  end

  def handle_event("close_new_token", _params, socket) do
    {:noreply,
     socket
     |> assign_token_form(Inference.change_token(socket.assigns.profile))
     |> push_event("close-modal", %{id: "new-inference-token-modal"})}
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
      <section id="ops-inference-profile">
        <div data-part="page-header">
          <div data-part="title-group">
            <h1>{@profile.name}</h1>
            <p>{@profile.description || "Stable model profile routed through Hive."}</p>
          </div>
        </div>

        <section :if={@generated_token} data-part="generated-token">
          <div data-part="generated-copy">
            <h2>Token created for {@profile.name}</h2>
            <p>
              Store this token now. Hive stores only its hash and cannot show it again.
            </p>
            <div data-part="read-only-value">
              <code>{@generated_token.value}</code>
              <.button
                id="copy-inference-token-button"
                variant="secondary"
                size="small"
                icon_only
                type="button"
                phx-hook="Clipboard"
                data-clipboard-value={@generated_token.value}
                aria-label="Copy token"
              >
                <.copy />
              </.button>
            </div>
          </div>
          <.button
            label="Dismiss"
            variant="secondary"
            size="small"
            phx-click="dismiss_generated_token"
          />
        </section>

        <.card title="Usage" icon="chart_column" data-part="usage-card">
          <:actions>
            <.usage_period_picker
              id="inference-profile-usage-date-range-picker"
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
              id="inference-profile-usage-chart"
              series={@usage_series}
              preset={@usage_preset}
              bucket={@usage_bucket}
              label={"Input and output token usage for #{@profile.name}"}
            />
          </.card_section>
          <.empty_card_section
            :if={!usage_chart_has_usage?(@usage_series)}
            title="No usage yet"
            data-part="empty-usage-chart-card-section"
          >
            <:image>
              <img src="/images/empty_line_chart_light.png" data-theme="light" />
              <img src="/images/empty_line_chart_dark.png" data-theme="dark" />
            </:image>
          </.empty_card_section>
        </.card>

        <.card title="Configuration" icon="lock" data-part="configuration-card">
          <:actions>
            <.edit_profile_modal
              profile_form={@profile_form}
              provider_options={@provider_options}
            />
            <.button
              label={if @profile.enabled, do: "Disable", else: "Enable"}
              variant="secondary"
              size="medium"
              phx-click="toggle_profile"
            />
          </:actions>
          <.card_section>
            <div data-part="definition-grid">
              <div data-part="definition-item">
                <span>Status</span>
                <% status = profile_status(@profile) %>
                <.badge label={status.label} color={status.color} style="light-fill" />
              </div>
              <div data-part="definition-item">
                <span>Upstream provider</span>
                <strong>{@profile.upstream_provider}</strong>
              </div>
              <div data-part="definition-item">
                <span>Upstream model</span>
                <code>{@profile.upstream_model}</code>
              </div>
              <div data-part="definition-item">
                <span>Input cost</span>
                <strong>{format_cost_per_million(@profile.input_cost_per_million)}</strong>
              </div>
              <div data-part="definition-item">
                <span>Output cost</span>
                <strong>{format_cost_per_million(@profile.output_cost_per_million)}</strong>
              </div>
              <div data-part="definition-item">
                <span>Last used</span>
                <strong>{last_used_label(@profile.last_used_at)}</strong>
              </div>
            </div>
          </.card_section>
        </.card>

        <.card title="Client configuration" icon="external_link" data-part="client-configuration-card">
          <.card_section>
            <p data-part="card-intro">
              Use a profile token as the authorization secret. Create one below and store it as
              <code>HIVE_INFERENCE_TOKEN</code>.
            </p>
            <div data-part="client-configuration-grid">
              <div data-part="definition-item">
                <span>Base address</span>
                <code>{@client_base_url}</code>
              </div>
              <div data-part="definition-item">
                <span>OpenAI-compatible model</span>
                <code>{@profile.name}</code>
              </div>
              <div data-part="definition-item">
                <span>Blick model</span>
                <code>hive/{@profile.name}</code>
              </div>
              <div data-part="definition-item">
                <span>Authorization header</span>
                <code>Bearer $HIVE_INFERENCE_TOKEN</code>
              </div>
            </div>
          </.card_section>
          <.card_section data-part="client-snippets-card-section">
            <div data-part="client-snippet">
              <span>opencode provider</span>
              <pre><code>{opencode_provider_snippet(@client_base_url, @profile)}</code></pre>
            </div>
            <div data-part="client-snippet">
              <span>blick.toml</span>
              <pre><code>{blick_snippet(@profile)}</code></pre>
            </div>
          </.card_section>
        </.card>

        <.card title="Tokens" icon="lock_password" data-part="tokens-card">
          <:actions>
            <.new_token_modal profile={@profile} token_form={@token_form} />
          </:actions>
          <.card_section>
            <p data-part="card-intro">
              Tokens are bound to this profile and can be revoked independently.
            </p>

            <div data-part="table-scroll">
              <.table
                id="inference-profile-tokens-table"
                rows={@tokens}
                row_navigate={fn token -> ~p"/ops/inference/tokens/#{token.id}" end}
              >
                <:col :let={token} label="Token">
                  <.text_cell label={token.name} />
                </:col>
                <:col :let={token} label="Status">
                  <% status = token_status(token) %>
                  <.badge_cell label={status.label} color={status.color} style="light-fill" />
                </:col>
                <:col :let={token} label="Created">
                  <.text_cell label={format_compact_datetime(token.inserted_at)} />
                </:col>
                <:col :let={token} label="Expires">
                  <.text_cell label={token_expiry_table_label(token.expires_at)} />
                </:col>
                <:col :let={token} label="Last used">
                  <.text_cell label={last_used_label(token.last_used_at)} />
                </:col>
                <:col :let={token} label="Usage">
                  <div data-part="token-usage-cell">
                    <% usage = token_usage(@token_usage_summaries, token) %>
                    <span>{format_count(usage.input_tokens)} in</span>
                    <small>{format_count(usage.output_tokens)} out</small>
                  </div>
                </:col>
                <:col :let={token} label="Cost">
                  <% usage = token_usage(@token_usage_summaries, token) %>
                  <.text_cell label={format_cost(usage.cost_usd)} />
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="lock_password"
                    title="No tokens"
                    subtitle="Create a token when repositories are ready to use this profile."
                  />
                </:empty_state>
              </.table>
            </div>
          </.card_section>
        </.card>
      </section>
    </Layouts.ops>
    """
  end

  attr :profile_form, :map, required: true
  attr :provider_options, :list, required: true

  defp edit_profile_modal(assigns) do
    ~H"""
    <.modal
      id="edit-inference-profile-modal"
      title="Edit profile"
      description="Update the upstream provider or model behind this stable profile."
      header_type="icon"
      header_size="large"
      on_dismiss="close_edit_profile"
    >
      <:trigger :let={attrs}>
        <.button
          label="Edit profile"
          variant="secondary"
          size="medium"
          phx-click="open_edit_profile"
          {attrs}
        >
          <:icon_left><.pencil /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="lock" />
      </:header_icon>

      <.form
        id="edit-inference-profile-form"
        for={@profile_form}
        phx-change="validate_profile"
        phx-submit="update_profile"
        data-part="form"
      >
        <.text_input
          id="edit-inference-profile-name"
          field={@profile_form[:name]}
          label="Profile name"
        />
        <.text_area
          id="edit-inference-profile-description"
          field={@profile_form[:description]}
          label="Description"
        />
        <div data-part="select-field">
          <span>Upstream provider</span>
          <.select
            id="edit-inference-profile-provider"
            name={@profile_form[:upstream_provider].name}
            on_value_change="profile_provider_changed"
            value={
              Phoenix.HTML.Form.normalize_value(
                "select",
                @profile_form[:upstream_provider].value
              )
            }
            label={if @provider_options == [], do: "No providers available", else: "Choose provider"}
            disabled={@provider_options == []}
          >
            <:item :for={provider <- @provider_options} value={provider.value} label={provider.label} />
          </.select>
        </div>
        <.text_input
          id="edit-inference-profile-model"
          field={@profile_form[:upstream_model]}
          label="Upstream model"
          placeholder={model_identifier_placeholder(@profile_form[:upstream_provider].value)}
        />
        <.text_input
          id="edit-inference-profile-input-cost"
          field={@profile_form[:input_cost_per_million]}
          label="Input cost per million tokens"
          input_type="number"
          min="0"
          step="0.000001"
        />
        <.text_input
          id="edit-inference-profile-output-cost"
          field={@profile_form[:output_cost_per_million]}
          label="Output cost per million tokens"
          input_type="number"
          min="0"
          step="0.000001"
        />
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_edit_profile"
            />
          </:action>
          <:action>
            <.button
              label="Save"
              size="medium"
              variant="primary"
              type="submit"
              form="edit-inference-profile-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  attr :profile, ModelBinding, required: true
  attr :token_form, :map, required: true

  defp new_token_modal(assigns) do
    ~H"""
    <.modal
      id="new-inference-token-modal"
      title="Create token"
      description={"Create a token that can only request #{@profile.name}."}
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_token"
    >
      <:trigger :let={attrs}>
        <.button
          label="Create token"
          size="medium"
          variant="primary"
          phx-click="open_new_token"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="lock" />
      </:header_icon>

      <.form
        id="new-inference-token-form"
        for={@token_form}
        phx-submit="create_token"
        data-part="form"
      >
        <.text_input
          id="new-inference-token-name"
          field={@token_form[:name]}
          label="Token name"
          placeholder="Repository automation"
        />
        <.text_input
          id="new-inference-token-expires-at"
          field={@token_form[:expires_at]}
          label="Expires at"
          placeholder="2026-07-01T12:00:00Z"
        />
      </.form>

      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              size="medium"
              type="button"
              phx-click="close_new_token"
            />
          </:action>
          <:action>
            <.button
              label="Create"
              size="medium"
              variant="primary"
              type="submit"
              form="new-inference-token-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp assign_profile(socket, id) do
    profile = Inference.get_profile!(id)

    socket
    |> assign(:page_title, "#{profile.name} · Inference · #{socket.assigns.product_name}")
    |> assign(OpenGraph.assigns(open_graph(profile)))
    |> assign(:profile, profile)
    |> assign(:tokens, profile.tokens)
    |> assign(:client_base_url, HiveWeb.Endpoint.url() <> "/v1")
    |> assign(:provider_options, provider_select_options(profile.upstream_provider))
    |> assign_profile_form(Inference.change_profile(profile))
    |> assign_token_form(Inference.change_token(profile))
    |> maybe_assign_usage()
  end

  defp assign_profile_form(socket, changeset) do
    assign(socket, :profile_form, to_form(changeset, as: :profile))
  end

  defp form_params(form) do
    form
    |> Map.get(:params, %{})
    |> case do
      params when is_map(params) -> params
      _params -> %{}
    end
  end

  defp selected_value(%{"value" => [value | _rest]}), do: value
  defp selected_value(%{"value" => value}) when is_binary(value), do: value
  defp selected_value(_params), do: nil

  defp assign_token_form(socket, changeset) do
    assign(socket, :token_form, to_form(changeset, as: :token))
  end

  defp assign_usage(%{assigns: %{profile: profile, usage_period: period}} = socket) do
    bucket = usage_period_bucket(socket.assigns.usage_preset, period)

    socket
    |> assign(:usage_bucket, bucket)
    |> assign(:usage_summary, Inference.usage_summary(profile, period))
    |> assign(:usage_series, Inference.usage_series(profile, period, bucket))
    |> assign(:token_usage_summaries, Inference.token_usage_summaries(profile, period))
  end

  defp assign_usage(socket), do: socket

  defp maybe_assign_usage(%{assigns: %{usage_period: _period}} = socket), do: assign_usage(socket)
  defp maybe_assign_usage(socket), do: socket

  defp token_usage(summaries, %Token{id: token_id}) do
    Map.get(summaries, token_id, empty_usage_summary())
  end

  defp usage_period_patch(%ModelBinding{} = profile, %URI{} = uri, "custom", %{
         "start" => start_at,
         "end" => end_at
       }) do
    query =
      uri.query
      |> Query.put("usage-date-range", "custom")
      |> Query.put("usage-start-date", start_at)
      |> Query.put("usage-end-date", end_at)
      |> Query.drop("usage-period")

    with_query(~p"/ops/inference/profiles/#{profile.id}", query)
  end

  defp usage_period_patch(%ModelBinding{} = profile, %URI{} = uri, preset, _value) do
    query =
      uri.query
      |> Query.put("usage-date-range", preset)
      |> Query.drop("usage-period")
      |> Query.drop("usage-start-date")
      |> Query.drop("usage-end-date")

    with_query(~p"/ops/inference/profiles/#{profile.id}", query)
  end

  defp with_query(path, ""), do: path
  defp with_query(path, query), do: path <> "?" <> query

  defp opencode_provider_snippet(base_url, %ModelBinding{name: name}) do
    """
    {
      "provider": {
        "hive": {
          "name": "Hive",
          "api": "openai",
          "env": ["HIVE_INFERENCE_TOKEN"],
          "options": {
            "baseURL": "#{base_url}"
          },
          "models": {
            "#{name}": {
              "id": "#{name}",
              "name": "#{name}"
            }
          }
        }
      }
    }
    """
    |> String.trim()
  end

  defp blick_snippet(%ModelBinding{name: name}) do
    """
    [agent]
    kind = "opencode"
    model = "hive/#{name}"
    """
    |> String.trim()
  end

  defp record_profile_audit(action, %ModelBinding{} = profile) do
    Audit.record(action, %{
      target_type: "inference_profile",
      target_id: profile.id,
      target_label: profile.name,
      metadata: %{
        "upstream_provider" => profile.upstream_provider,
        "upstream_model" => profile.upstream_model,
        "input_cost_per_million" => profile.input_cost_per_million,
        "output_cost_per_million" => profile.output_cost_per_million,
        "path" => "/ops/inference/profiles/#{profile.id}"
      }
    })
  end

  defp record_token_audit(action, %ModelBinding{} = profile, %Token{} = token) do
    Audit.record(action, %{
      target_type: "inference_token",
      target_id: token.id,
      target_label: token.name,
      metadata: %{
        "profile_id" => profile.id,
        "profile_name" => profile.name,
        "path" => "/ops/inference/profiles/#{profile.id}"
      }
    })
  end
end
