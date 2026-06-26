defmodule HiveWeb.OpsLive.InferenceProviders do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Audit
  alias Hive.Inference
  alias Hive.Inference.Provider
  alias Hive.Ops.Policy
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description: "Manage upstream inference providers configured for the relay.",
      section_label: "Ops",
      highlights: ["Provider endpoints", "Credential status", "Profile references"],
      id: "ops-inference-providers",
      path: "/ops/inference/providers",
      title: "Inference providers"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok,
         socket
         |> put_flash(:error, "Log in to review inference providers.")
         |> redirect(to: ~p"/login?return_to=/ops/inference/providers")}

      not Policy.authorize?(:inference_profile_manage, user, nil) ->
        {:ok,
         socket
         |> put_flash(:error, "Only instance admins can review inference providers.")
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, "Inference providers · #{socket.assigns.product_name}")
         |> assign(OpenGraph.assigns(open_graph()))
         |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
         |> assign_providers()}
    end
  end

  @impl true
  def handle_event("validate_provider", %{"provider" => params}, socket) do
    changeset =
      %Provider{}
      |> Inference.change_provider(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_provider_form(socket, changeset)}
  end

  def handle_event("create_provider", %{"provider" => params}, socket) do
    case Inference.create_provider(params) do
      {:ok, provider} ->
        record_provider_audit(:"inference_provider.created", provider)

        {:noreply,
         socket
         |> put_flash(:info, "Provider created.")
         |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
         |> assign_providers()
         |> push_event("close-modal", %{id: "new-inference-provider-modal"})}

      {:error, changeset} ->
        {:noreply, assign_provider_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  def handle_event("open_new_provider", _params, socket) do
    {:noreply,
     socket
     |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
     |> push_event("open-modal", %{id: "new-inference-provider-modal"})}
  end

  def handle_event("close_new_provider", _params, socket) do
    {:noreply,
     socket
     |> assign_provider_form(Inference.change_provider(%Provider{}, %{timeout: 300_000}))
     |> push_event("close-modal", %{id: "new-inference-provider-modal"})}
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
      <section id="ops-inference-providers">
        <div data-part="page-header">
          <div data-part="title-group">
            <h1>Providers</h1>
            <p>
              Create upstream endpoints that profiles can target. Credentials are encrypted and
              are never shown after saving.
            </p>
          </div>
        </div>

        <.card title="Providers" icon="server" data-part="providers-card">
          <:actions>
            <.new_provider_modal provider_form={@provider_form} />
          </:actions>
          <.card_section>
            <p data-part="card-intro">
              Runtime-managed and environment-backed endpoints with profile references.
            </p>

            <div data-part="table-scroll">
              <.table id="inference-providers-table" rows={@providers}>
                <:col :let={provider} label="Provider">
                  <.text_and_description_cell
                    icon="server"
                    label={provider.id}
                    description={provider_description(provider)}
                  />
                </:col>
                <:col :let={provider} label="Status">
                  <% status = provider_status(provider) %>
                  <.badge_cell label={status.label} color={status.color} style="light-fill" />
                </:col>
                <:col :let={provider} label="Endpoint">
                  <div data-part="route-cell">
                    <code :if={provider.base_url}>{provider.base_url}</code>
                    <span :if={!provider.base_url}>Not configured</span>
                  </div>
                </:col>
                <:col :let={provider} label="Credential">
                  <.text_cell label={credential_label(provider)} />
                </:col>
                <:col :let={provider} label="Timeout">
                  <.text_cell label={timeout_label(provider.timeout)} />
                </:col>
                <:col :let={provider} label="Profiles">
                  <.text_cell label={profile_count_label(provider.profile_count)} />
                </:col>
                <:empty_state>
                  <.table_empty_state
                    icon="server"
                    title="No inference providers"
                    subtitle="Create a provider before creating profiles that route to it."
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

  attr :provider_form, :map, required: true

  defp new_provider_modal(assigns) do
    ~H"""
    <.modal
      id="new-inference-provider-modal"
      title="Create provider"
      description="Add an upstream endpoint that profiles can route requests to."
      header_type="icon"
      header_size="large"
      on_dismiss="close_new_provider"
    >
      <:trigger :let={attrs}>
        <.button
          label="Create provider"
          size="medium"
          variant="primary"
          phx-click="open_new_provider"
          {attrs}
        >
          <:icon_left><.circle_plus /></:icon_left>
        </.button>
      </:trigger>
      <:header_icon>
        <.icon name="server" />
      </:header_icon>

      <.form
        id="new-inference-provider-form"
        for={@provider_form}
        phx-change="validate_provider"
        phx-submit="create_provider"
        data-part="form"
      >
        <.text_input
          id="new-inference-provider-key"
          field={@provider_form[:key]}
          label="Provider key"
          placeholder="fireworks"
        />
        <.text_input
          id="new-inference-provider-endpoint"
          field={@provider_form[:base_url]}
          label="Endpoint"
          input_type="url"
          placeholder="https://api.fireworks.ai/inference/v1"
        />
        <.text_input
          id="new-inference-provider-credential"
          field={@provider_form[:api_key]}
          label="Credential"
          input_type="password"
          placeholder="provider-token"
        />
        <.text_input
          id="new-inference-provider-timeout"
          field={@provider_form[:timeout]}
          label="Timeout in milliseconds"
          input_type="number"
          min="1"
          step="1"
          placeholder="300000"
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
              phx-click="close_new_provider"
            />
          </:action>
          <:action>
            <.button
              label="Create"
              size="medium"
              variant="primary"
              type="submit"
              form="new-inference-provider-form"
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp provider_status(%{configured?: false}), do: %{label: "Missing", color: "warning"}

  defp provider_status(%{endpoint_configured?: false}),
    do: %{label: "No endpoint", color: "destructive"}

  defp provider_status(%{credential_configured?: false}),
    do: %{label: "No credential", color: "warning"}

  defp provider_status(_provider), do: %{label: "Ready", color: "success"}

  defp provider_description(%{source: :database}), do: "Managed in Hive"
  defp provider_description(%{source: :environment}), do: "Configured from the environment"
  defp provider_description(_provider), do: "Referenced by profiles but not configured"

  defp credential_label(%{credential_configured?: true}), do: "Configured"
  defp credential_label(_provider), do: "Missing"

  defp timeout_label(nil), do: "Not configured"

  defp timeout_label(timeout) when is_integer(timeout) and rem(timeout, 1_000) == 0 do
    "#{div(timeout, 1_000)} #{pluralize("second", div(timeout, 1_000))}"
  end

  defp timeout_label(timeout) when is_integer(timeout) do
    "#{timeout} #{pluralize("millisecond", timeout)}"
  end

  defp profile_count_label(count), do: "#{count} #{pluralize("profile", count)}"

  defp pluralize(word, 1), do: word
  defp pluralize(word, _count), do: word <> "s"

  defp assign_providers(socket) do
    assign(socket, :providers, Inference.list_provider_configs())
  end

  defp assign_provider_form(socket, changeset) do
    assign(socket, :provider_form, to_form(changeset, as: :provider))
  end

  defp record_provider_audit(action, %Provider{} = provider) do
    Audit.record(action, %{
      target_type: "inference_provider",
      target_id: provider.id,
      target_label: provider.key,
      metadata: %{
        "base_url" => provider.base_url,
        "credential_configured" => Provider.credential_configured?(provider),
        "path" => "/ops/inference/providers",
        "timeout" => provider.timeout
      }
    })
  end
end
