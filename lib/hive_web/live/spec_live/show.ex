defmodule HiveWeb.SpecLive.Show do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Specs
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.SpecComponents

  def open_graph(spec) do
    %{
      author: author_data(spec),
      description: spec_summary(spec),
      eyebrow: "Spec #{spec_number(spec)}",
      highlights: [
        spec_number(spec),
        "#{length(spec.comments)} comments",
        visibility_label(Specs.effective_visibility(spec)),
        status_label(spec.status)
      ],
      id: "spec-#{spec.number}",
      path: "/specs/#{spec.number}",
      title: spec.title
    }
  end

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, socket.assigns.current_user) do
      {:ok,
       socket
       |> assign(:page_title, "#{spec.title} · #{socket.assigns.product_name}")
       |> assign(OpenGraph.assigns(open_graph(spec)))
       |> assign(:spec, spec)
       |> assign(:can_edit?, Specs.can_edit?(spec, socket.assigns.current_user))
       |> assign(:expanded_revision_rows, [])
       |> assign_comment_form(Specs.change_comment())}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only organization members can view this private spec.")
       |> redirect(to: ~p"/specs")}
    end
  end

  @impl true
  def handle_event("toggle-expand", %{"row-key" => row_key}, socket) do
    expanded_rows = socket.assigns.expanded_revision_rows

    expanded_rows =
      if row_key in expanded_rows do
        List.delete(expanded_rows, row_key)
      else
        [row_key | expanded_rows]
      end

    {:noreply, assign(socket, :expanded_revision_rows, expanded_rows)}
  end

  @impl true
  def handle_event("comment", %{"comment" => params}, socket) do
    case Specs.add_comment(socket.assigns.spec, params, socket.assigns.current_user) do
      {:ok, _comment} ->
        spec = Specs.get_spec!(socket.assigns.spec.id)

        {:noreply,
         socket
         |> put_flash(:info, "Comment added.")
         |> assign(:spec, spec)
         |> assign(OpenGraph.assigns(open_graph(spec)))
         |> assign_comment_form(Specs.change_comment())}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Sign in to comment.")}

      {:error, changeset} ->
        {:noreply, assign_comment_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  defp assign_comment_form(socket, changeset) do
    assign(socket, :comment_form, to_form(interpolate_errors(changeset), as: :comment))
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

  defp status_label(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp source_label(%{source_feature_request: %{title: title}}), do: "Source: #{title}"
  defp source_label(_spec), do: "Created directly"

  defp visibility_label(:private), do: "Private"
  defp visibility_label(_visibility), do: "Public"

  defp spec_number(%{number: number}) when is_integer(number), do: "##{number}"
  defp spec_number(_spec), do: "#?"

  defp spec_summary(%{summary: summary}) when is_binary(summary) and summary != "", do: summary

  defp spec_summary(spec),
    do:
      "#{visibility_label(Specs.effective_visibility(spec))} · #{status_label(spec.status)} · #{source_label(spec)}"

  defp author_data(%{created_by_user: %{email: email}}) when is_binary(email) do
    handle =
      email
      |> String.split("@", parts: 2)
      |> List.first()
      |> then(&"@#{&1}")

    %{handle: handle, initials: String.first(handle |> String.trim_leading("@")) || "?"}
  end

  defp author_data(_spec), do: nil

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
      settings_enabled?={@settings_enabled?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <SpecComponents.show
        spec={@spec}
        comment_form={@comment_form}
        can_edit?={@can_edit?}
        signed_in?={@signed_in?}
        user_name={@user_name}
        expanded_revision_rows={@expanded_revision_rows}
      />
    </Layouts.dashboard>
    """
  end
end
