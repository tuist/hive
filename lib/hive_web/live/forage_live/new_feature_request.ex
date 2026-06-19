defmodule HiveWeb.ForageLive.NewFeatureRequest do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def open_graph do
    %{
      description: "Capture a public feature request, bug report, or feedback item.",
      eyebrow: "Forage",
      highlights: ["Public items", "Actionable context", "Contributor signal"],
      id: "forage-new",
      path: "/forage/new",
      title: "New forage item"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    source = Forage.get_source!(:feature_requests)

    if Forage.can_create?(source, socket.assigns.current_user) do
      {:ok,
       socket
       |> assign(:page_title, "New forage item · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(open_graph()))
       |> assign_form(Forage.change_forage_item())}
    else
      {:ok,
       socket
       |> put_flash(:error, "Log in to submit forage items.")
       |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("validate", %{"forage_item" => params}, socket) do
    changeset =
      %FeatureRequest{}
      |> Forage.change_forage_item(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"forage_item" => params}, socket) do
    case Forage.create_forage_item(params, socket.assigns.current_user) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Forage item submitted.")
         |> push_navigate(to: ~p"/forage")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :forage_item))
  end

  # Noora's inputs render an error's raw message and drop its opts, so
  # interpolate the bindings (e.g. `%{count}`) into the message here
  # before the form reaches them.
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
      admin?={@admin?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
      specs_have_new_activity?={@specs_have_new_activity?}
    >
      <ForageComponents.new_item form={@form} user_name={@user_name} />
    </Layouts.dashboard>
    """
  end
end
