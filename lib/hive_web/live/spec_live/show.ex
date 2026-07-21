defmodule HiveWeb.SpecLive.Show do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Accounts.User
  alias Hive.Notifications
  alias Hive.Specs
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.SpecComponents

  def open_graph(spec) do
    %{
      author: author_data(spec),
      description: spec_summary(spec),
      section_label: dgettext("dashboard_specs", "Spec %{number}", number: spec_number(spec)),
      highlights: [
        spec_number(spec),
        dgettext("dashboard_specs", "%{count} comments", count: length(spec.comments)),
        visibility_label(Specs.effective_visibility(spec)),
        status_label(spec.status)
      ],
      id: "spec-#{spec.number}",
      path: "/specs/#{spec.number}",
      title: spec.title
    }
  end

  def slack_unfurl(uri, %{"number" => number}) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, nil) do
      Hive.Slack.Unfurl.BlockKit.open_graph(uri, open_graph(spec))
    else
      :skip
    end
  end

  @impl true
  def mount(%{"number" => number}, _session, socket) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, socket.assigns.current_user) do
      viewer_last_viewed_at = Specs.last_viewed_at(spec, socket.assigns.current_user)
      if connected?(socket), do: Specs.mark_viewed(spec, socket.assigns.current_user)

      {:ok,
       socket
       |> maybe_subscribe_to_spec(spec)
       |> assign(
         :page_title,
         dgettext("dashboard_specs", "%{title} · %{product}",
           title: spec.title,
           product: socket.assigns.product_name
         )
       )
       |> assign(OpenGraph.assigns(open_graph(spec)))
       |> assign(:atom_feed, %{
         title: dgettext("dashboard_specs", "Hive · Specs"),
         atom_href: "/specs/atom.xml",
         rss_href: "/specs/rss.xml"
       })
       |> assign_spec(spec)
       |> assign(
         :following?,
         Notifications.subscribed?(socket.assigns.current_user, :spec_updates, spec.id)
       )
       |> assign(:can_edit?, Specs.can_edit?(spec, socket.assigns.current_user))
       |> assign(
         :can_request_review?,
         Specs.can_request_review?(spec, socket.assigns.current_user)
       )
       |> assign(:viewer_last_viewed_at, viewer_last_viewed_at)
       |> assign(:expanded_revision_rows, [])
       |> assign(:editing_comment_id, nil)
       |> assign_comment_form(Specs.change_comment())
       |> assign_edit_comment_form(Specs.change_comment())}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         dgettext("dashboard_specs", "Only organization members can view this private spec.")
       )
       |> redirect(to: ~p"/specs")}
    end
  end

  @impl true
  def handle_event("follow", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply,
     put_flash(socket, :error, dgettext("dashboard_specs", "Sign in to follow this spec."))}
  end

  def handle_event("follow", _params, socket) do
    {:ok, _subscription} =
      Notifications.follow_spec(socket.assigns.current_user, socket.assigns.spec.id,
        cadence: :immediate
      )

    {:noreply,
     socket
     |> assign(:following?, true)
     |> put_flash(:info, dgettext("dashboard_specs", "You are following this spec."))}
  end

  def handle_event("unfollow", _params, socket) do
    Notifications.unsubscribe(socket.assigns.current_user, :spec_updates, socket.assigns.spec.id)

    {:noreply,
     socket
     |> assign(:following?, false)
     |> put_flash(:info, dgettext("dashboard_specs", "You are no longer following this spec."))}
  end

  @impl true
  def handle_event("request_review", _params, socket) do
    case Specs.request_review(socket.assigns.spec, socket.assigns.current_user) do
      {:ok, _spec} ->
        {:noreply, put_flash(socket, :info, dgettext("dashboard_specs", "Review requested."))}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "Only organization members can request review.")
         )}
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
  def handle_event("set_status", %{"status" => status}, socket) do
    spec = socket.assigns.spec

    cond do
      not socket.assigns.can_edit? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "Only organization members can change spec status.")
         )}

      to_string(spec.status) == status ->
        {:noreply, socket}

      true ->
        attrs = %{"status" => status, "lock_version" => spec.lock_version}

        case Specs.update_spec(spec, attrs, socket.assigns.current_user) do
          {:ok, updated} ->
            spec = Specs.get_spec!(updated.id)

            {:noreply,
             socket
             |> put_flash(
               :info,
               dgettext("dashboard_specs", "Spec marked as %{status}.",
                 status: status_label(spec.status)
               )
             )
             |> assign_spec(spec)
             |> assign(OpenGraph.assigns(open_graph(spec)))}

          {:error, :unauthorized} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("dashboard_specs", "Only organization members can change spec status.")
             )}

          {:error, :locked} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext(
                 "dashboard_specs",
                 "This spec is being written by another request. Try again in a moment."
               )
             )}

          {:error, _changeset} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("dashboard_specs", "Couldn't update the spec status.")
             )}
        end
    end
  end

  @impl true
  def handle_event("comment", %{"comment" => params}, socket) do
    case Specs.add_comment(socket.assigns.spec, params, socket.assigns.current_user) do
      {:ok, _comment} ->
        spec = Specs.get_spec!(socket.assigns.spec.id)

        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_specs", "Comment added."))
         |> assign(:following?, true)
         |> assign_spec(spec)
         |> assign(OpenGraph.assigns(open_graph(spec)))
         |> assign_comment_form(Specs.change_comment())}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_specs", "Sign in to comment."))}

      {:error, changeset} ->
        {:noreply, assign_comment_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  @impl true
  def handle_event("edit_comment", %{"id" => comment_id}, socket) do
    with {:ok, comment} <- find_comment(socket, comment_id),
         true <- Specs.can_edit_comment?(comment, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:editing_comment_id, comment.id)
       |> assign_edit_comment_form(Specs.change_comment(comment))}
    else
      _error ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "Only the comment author can edit this comment.")
         )}
    end
  end

  @impl true
  def handle_event(
        "validate_comment_edit",
        %{"comment_edit" => params, "comment_id" => comment_id},
        socket
      ) do
    with {:ok, comment} <- find_comment(socket, comment_id),
         true <- Specs.can_edit_comment?(comment, socket.assigns.current_user) do
      changeset =
        comment
        |> Specs.change_comment(params)
        |> Map.put(:action, :validate)

      {:noreply,
       socket
       |> assign(:editing_comment_id, comment.id)
       |> assign_edit_comment_form(changeset)}
    else
      _error ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "Only the comment author can edit this comment.")
         )}
    end
  end

  @impl true
  def handle_event(
        "update_comment",
        %{"comment_edit" => params, "comment_id" => comment_id},
        socket
      ) do
    with {:ok, comment} <- find_comment(socket, comment_id),
         {:ok, _comment} <- Specs.update_comment(comment, params, socket.assigns.current_user) do
      spec = Specs.get_spec!(socket.assigns.spec.id)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("dashboard_specs", "Comment updated."))
       |> assign_spec(spec)
       |> assign(OpenGraph.assigns(open_graph(spec)))
       |> clear_comment_edit()}
    else
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "Only the comment author can edit this comment.")
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:editing_comment_id, comment_id)
         |> assign_edit_comment_form(Map.put(changeset, :action, :validate))}

      _error ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_specs", "Comment not found."))}
    end
  end

  @impl true
  def handle_event("cancel_comment_edit", _params, socket) do
    {:noreply, clear_comment_edit(socket)}
  end

  @impl true
  def handle_event("close_delete_comment", %{"id" => comment_id}, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: delete_comment_modal_id(comment_id)})}
  end

  @impl true
  def handle_event("delete_comment", %{"id" => comment_id}, socket) do
    with {:ok, comment} <- find_comment(socket, comment_id),
         {:ok, _comment} <- Specs.delete_comment(comment, socket.assigns.current_user) do
      spec = Specs.get_spec!(socket.assigns.spec.id)

      {:noreply,
       socket
       |> put_flash(:info, dgettext("dashboard_specs", "Comment deleted."))
       |> push_event("close-modal", %{id: delete_comment_modal_id(comment_id)})
       |> assign_spec(spec)
       |> assign(OpenGraph.assigns(open_graph(spec)))
       |> clear_comment_edit()}
    else
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_specs", "Only the comment author can delete this comment.")
         )}

      _error ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_specs", "Comment not found."))}
    end
  end

  defp assign_comment_form(socket, changeset) do
    assign(socket, :comment_form, to_form(interpolate_errors(changeset), as: :comment))
  end

  defp assign_spec(socket, spec) do
    socket
    |> assign(:spec, spec)
    |> assign(
      :comment_mention_suggestions,
      comment_mention_suggestions(spec, socket.assigns.current_user)
    )
  end

  defp assign_edit_comment_form(socket, changeset) do
    assign(socket, :edit_comment_form, to_form(interpolate_errors(changeset), as: :comment_edit))
  end

  defp maybe_subscribe_to_spec(socket, spec) do
    if connected?(socket) do
      Specs.subscribe_to_spec(spec)
    end

    socket
  end

  defp clear_comment_edit(socket) do
    socket
    |> assign(:editing_comment_id, nil)
    |> assign_edit_comment_form(Specs.change_comment())
  end

  defp find_comment(socket, comment_id) do
    case Enum.find(socket.assigns.spec.comments, &(&1.id == comment_id)) do
      nil -> :error
      comment -> {:ok, comment}
    end
  end

  defp delete_comment_modal_id(comment_id), do: "delete-comment-modal-#{comment_id}"

  defp comment_mention_suggestions(spec, current_user) do
    [current_user, spec.created_by_user, spec.updated_by_user]
    |> Kernel.++(Enum.map(spec.comments, & &1.user))
    |> Kernel.++(Enum.map(spec.revisions, & &1.user))
    |> Enum.filter(&match?(%User{}, &1))
    |> Enum.uniq_by(& &1.email)
    |> Enum.map(&mention_suggestion/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&mention_suggestion_sort_key/1)
  end

  defp mention_suggestion(%User{email: email} = user) when is_binary(email) do
    with [local_part, _domain] <- String.split(email, "@", parts: 2),
         token when token != "" <- mention_token(local_part) do
      %{token: token, name: mention_name(user), email: email}
    else
      _invalid -> nil
    end
  end

  defp mention_suggestion(_user), do: nil

  defp mention_suggestion_sort_key(%{name: name, email: email}) do
    {name || email, email}
    |> then(fn {name, email} -> {String.downcase(name), String.downcase(email)} end)
  end

  defp mention_name(%User{name: name}) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      name -> name
    end
  end

  defp mention_name(_user), do: nil

  defp mention_token(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9._-]+/, "-")
    |> String.slice(0, 39)
    |> String.trim(".-_")
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

  defp status_label(:draft), do: dgettext("dashboard_specs", "Draft")
  defp status_label(:proposed), do: dgettext("dashboard_specs", "Proposed")
  defp status_label(:approved), do: dgettext("dashboard_specs", "Approved")
  defp status_label(:paused), do: dgettext("dashboard_specs", "Paused")
  defp status_label(:rejected), do: dgettext("dashboard_specs", "Rejected")
  defp status_label(:in_progress), do: dgettext("dashboard_specs", "In progress")
  defp status_label(:shipped), do: dgettext("dashboard_specs", "Shipped")
  defp status_label(:archived), do: dgettext("dashboard_specs", "Archived")

  defp status_label(status),
    do: status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  defp source_label(%{source_feature_request: %{title: title}}),
    do: dgettext("dashboard_specs", "Source: %{title}", title: title)

  defp source_label(_spec), do: dgettext("dashboard_specs", "Created directly")

  defp visibility_label(:private), do: dgettext("dashboard_specs", "Private")
  defp visibility_label(_visibility), do: dgettext("dashboard_specs", "Public")

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
      <SpecComponents.show
        spec={@spec}
        following?={@following?}
        comment_form={@comment_form}
        edit_comment_form={@edit_comment_form}
        mention_suggestions={@comment_mention_suggestions}
        can_edit?={@can_edit?}
        can_request_review?={@can_request_review?}
        current_user={@current_user}
        editing_comment_id={@editing_comment_id}
        signed_in?={@signed_in?}
        current_path={@current_path}
        expanded_revision_rows={@expanded_revision_rows}
        viewer_last_viewed_at={@viewer_last_viewed_at}
      />
    </Layouts.dashboard>
    """
  end
end
