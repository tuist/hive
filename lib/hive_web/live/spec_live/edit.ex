defmodule HiveWeb.SpecLive.Edit do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Domains
  alias Hive.Specs
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.SpecComponents

  def open_graph(spec) do
    %{
      description: "Edit an existing domain proposal.",
      section_label: "Spec",
      highlights: ["Editable proposal", "Optimistic locking", "Member only"],
      id: "specs-edit-#{spec.number}",
      path: "/specs/#{spec.number}/edit",
      title: "Edit #{spec.title}"
    }
  end

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_edit?(spec, socket.assigns.current_user) do
      {:ok,
       socket
       |> assign(:page_title, "Edit #{spec.title} · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(open_graph(spec)))
       |> assign(:domains, Domains.list_domains())
       |> assign(:spec, spec)
       |> assign_form(Specs.change_spec(spec))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only organization members can edit specs.")
       |> redirect(to: ~p"/specs/#{spec.number}")}
    end
  end

  @impl true
  def handle_event("validate", %{"spec" => params}, socket) do
    changeset =
      socket.assigns.spec
      |> Specs.change_spec(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"spec" => params}, socket) do
    case Specs.update_spec(socket.assigns.spec, params, socket.assigns.current_user) do
      {:ok, spec} ->
        {:noreply,
         socket
         |> put_flash(:info, "Spec updated.")
         |> push_navigate(to: ~p"/specs/#{spec.number}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only organization members can edit specs.")}

      {:error, :locked} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Another update is in progress for this spec. Try again in a moment."
         )}

      {:error, %{errors: [lock_version: _error]} = changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "This spec changed elsewhere. Pull the latest version before saving."
         )
         |> assign_form(Map.put(changeset, :action, :validate))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :spec))
  end

  defp interpolate_errors(%Ecto.Changeset{} = changeset) do
    Map.update!(changeset, :errors, fn errors -> Enum.map(errors, &interpolate_error/1) end)
  end

  defp interpolate_error({field, {message, opts}}) do
    interpolated =
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)

    {field, {interpolated, opts}}
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
      <SpecComponents.spec_form
        form={@form}
        title="Edit spec"
        action_label="Save spec"
        domains={@domains}
        source={@spec.source_feature_request}
      />
    </Layouts.dashboard>
    """
  end
end
