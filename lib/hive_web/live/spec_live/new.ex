defmodule HiveWeb.SpecLive.New do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Specs
  alias Hive.Specs.Spec
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.SpecComponents

  def open_graph do
    %{
      description: "Draft an editable proposal for buildable work.",
      eyebrow: "Spec",
      highlights: ["Editable proposal", "Forage source", "Bee-ready work"],
      id: "specs-new",
      path: "/specs/new",
      title: "New spec"
    }
  end

  @impl true
  def mount(params, _session, socket) do
    if Specs.can_create?(socket.assigns.current_user) do
      source = source(params)

      attrs =
        case source do
          nil ->
            %{"status" => "draft"}

          source ->
            %{
              "title" => source.title,
              "body" => source.description,
              "status" => "draft",
              "source_feature_request_id" => source.id
            }
        end

      {:ok,
       socket
       |> assign(:page_title, "New spec · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(open_graph()))
       |> assign(:source, source)
       |> assign_form(Specs.change_spec(%Spec{}, attrs))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only organization members can create specs.")
       |> redirect(to: ~p"/specs")}
    end
  end

  @impl true
  def handle_event("validate", %{"spec" => params}, socket) do
    changeset =
      %Spec{}
      |> Specs.change_spec(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"spec" => params}, socket) do
    case Specs.create_spec(params, socket.assigns.current_user) do
      {:ok, spec} ->
        {:noreply,
         socket
         |> put_flash(:info, "Spec created.")
         |> push_navigate(to: ~p"/specs/#{spec.id}")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only organization members can create specs.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp source(%{"source_feature_request_id" => id}) when is_binary(id) and id != "" do
    Forage.get_feature_request!(id)
  end

  defp source(_params), do: nil

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
      <SpecComponents.spec_form
        form={@form}
        title="New spec"
        action_label="Create spec"
        source={@source}
      />
    </Layouts.dashboard>
    """
  end
end
