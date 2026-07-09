defmodule HiveWeb.SpecLive.New do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Projects
  alias Hive.Specs
  alias Hive.Specs.Spec
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.SpecComponents

  def open_graph do
    %{
      description: dgettext("dashboard_specs", "Draft an editable proposal for buildable work."),
      section_label: dgettext("dashboard_specs", "Spec"),
      highlights: [
        dgettext("dashboard_specs", "Editable proposal"),
        dgettext("dashboard_specs", "Forage source"),
        dgettext("dashboard_specs", "Build-ready work")
      ],
      id: "specs-new",
      path: "/specs/new",
      title: dgettext("dashboard_specs", "New spec")
    }
  end

  @impl true
  def mount(params, _session, socket) do
    if Specs.can_create?(socket.assigns.current_user) do
      source = source(params)
      projects = Projects.list_projects()
      default_project_id = projects |> List.first() |> then(&(&1 && &1.id))

      attrs =
        case source do
          nil ->
            %{"status" => "draft", "project_id" => default_project_id}

          source ->
            %{
              "title" => source.title,
              "body" => source.description,
              "status" => "draft",
              "project_id" => default_project_id,
              "source_feature_request_id" => source.id
            }
        end

      {:ok,
       socket
       |> assign(
         :page_title,
         dgettext("dashboard_specs", "New spec · %{product}",
           product: socket.assigns.product_name
         )
       )
       |> assign(OpenGraph.assigns(open_graph()))
       |> assign(:projects, projects)
       |> assign(:domains, domains_for_project(default_project_id))
       |> assign(:source, source)
       |> assign_form(Specs.change_spec(%Spec{}, attrs))}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("dashboard_specs", "Only organization members can create specs.")
       )
       |> redirect(to: ~p"/specs")}
    end
  end

  @impl true
  def handle_event("validate", %{"spec" => params}, socket) do
    changeset =
      %Spec{}
      |> Specs.change_spec(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:domains, domains_for_project(params["project_id"]))
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"spec" => params}, socket) do
    case Specs.create_spec(params, socket.assigns.current_user) do
      {:ok, spec} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_specs", "Spec created."))
         |> push_navigate(to: ~p"/specs/#{spec.number}")}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "Only organization members can create specs.")
         )}

      {:error, :locked} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "A spec write is in progress. Try again in a moment.")
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:domains, domains_for_project(params["project_id"]))
         |> assign_form(changeset)}
    end
  end

  defp source(%{"source_feature_request_id" => id}) when is_binary(id) and id != "" do
    Forage.get_feature_request!(id)
  end

  defp source(_params), do: nil

  defp domains_for_project(project_id) when is_binary(project_id) and project_id != "",
    do: Projects.list_domains_for_project(project_id)

  defp domains_for_project(_project_id), do: []

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
        title={dgettext("dashboard_specs", "New spec")}
        action_label={dgettext("dashboard_specs", "Create spec")}
        projects={@projects}
        domains={@domains}
        source={@source}
      />
    </Layouts.dashboard>
    """
  end
end
