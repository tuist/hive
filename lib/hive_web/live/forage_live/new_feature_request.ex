defmodule HiveWeb.ForageLive.NewFeatureRequest do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Forage.FeatureRequest
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    source = Forage.get_source!(:feature_requests)

    if Forage.can_create?(source, socket.assigns.current_user) do
      {:ok,
       socket
       |> assign(:page_title, "New feature request · #{socket.assigns.product_name}")
       |> assign_form(Forage.change_feature_request())}
    else
      {:ok,
       socket
       |> put_flash(:error, "Log in to submit feature requests.")
       |> redirect(to: ~p"/login")}
    end
  end

  @impl true
  def handle_event("validate", %{"feature_request" => params}, socket) do
    changeset =
      %FeatureRequest{}
      |> Forage.change_feature_request(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"feature_request" => params}, socket) do
    case Forage.create_feature_request(params, socket.assigns.current_user) do
      {:ok, _feature_request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Feature request submitted.")
         |> push_navigate(to: ~p"/forage/feature-requests")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(interpolate_errors(changeset), as: :feature_request))
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
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <ForageComponents.new_feature_request form={@form} user_name={@user_name} />
    </Layouts.dashboard>
    """
  end
end
