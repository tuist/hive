defmodule HiveWeb.ForageLive.Show do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Flights
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.FeatureRequest
  alias Hive.Notifications
  alias Hive.Specs
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph

  def item_path(%{id: item_id}), do: item_path_from_id!(item_id)

  def item_path_from_id!("manual:" <> id), do: ~p"/forage/items/manual/#{id}"
  def item_path_from_id!("github_issue:" <> id), do: ~p"/forage/items/github-issue/#{id}"
  def item_path_from_id!("grafana_alert:" <> id), do: ~p"/forage/items/grafana-alert/#{id}"

  def item_path_from_id!(_item_id), do: ~p"/forage"

  def item_id("manual", id), do: {:ok, "manual:" <> id}
  def item_id("github-issue", id), do: {:ok, "github_issue:" <> id}
  def item_id("grafana-alert", id), do: {:ok, "grafana_alert:" <> id}
  def item_id(_origin, _id), do: :error

  def open_graph(item) do
    %{
      description: item_description(item),
      section_label: Forage.item_type_label(item.type),
      highlights:
        [
          Forage.item_status_label(item.status),
          item.source_label,
          comments_highlight(item)
        ]
        |> Enum.reject(&is_nil/1),
      id: open_graph_id(item),
      path: item_path(item),
      title: item.title
    }
  end

  def slack_unfurl(uri, %{"origin" => origin, "id" => id}) do
    with {:ok, item_id} <- item_id(origin, id),
         {:ok, item} <- Forage.get_item_for_user(item_id, nil) do
      Hive.Slack.Unfurl.BlockKit.open_graph(uri, open_graph(item))
    else
      _error -> :skip
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       :page_title,
       dgettext("dashboard_forage", "Forage item · %{product}",
         product: socket.assigns.product_name
       )
     )
     |> assign(:item, nil)
     |> assign(:following?, false)
     |> assign(:can_create_spec?, Specs.can_create?(socket.assigns.current_user))
     |> assign(:can_edit_item?, false)
     |> assign(:can_comment_item?, false)
     |> assign(:editing_item?, false)
     |> assign_item_edit_form(Forage.change_forage_item())
     |> assign_comment_form(Forage.change_comment())
     |> assign(:editing_comment_id, nil)
     |> assign_edit_comment_form(Forage.change_comment())
     |> assign(:coding_runs, [])
     |> assign(:coding_repositories, [])
     |> assign(:coding_runner_enabled?, false)
     |> assign(:can_start_coding_run?, false)
     |> assign(
       :coding_run_form,
       to_form(%{"repository_id" => "", "objective" => "investigate"}, as: :coding_run)
     )
     |> assign(:atom_feed, %{
       title: dgettext("dashboard_forage", "Hive · Forage"),
       atom_href: "/forage/atom.xml",
       rss_href: "/forage/rss.xml"
     })}
  end

  @impl true
  def handle_params(%{"origin" => origin, "id" => id}, _uri, socket) do
    with {:ok, item_id} <- item_id(origin, id),
         {:ok, item} <-
           Forage.get_item_for_user(item_id, socket.assigns.current_user,
             fetch_github_comments?: true
           ) do
      if connected?(socket), do: CodingRuns.subscribe(item.id)
      {:noreply, assign_item(socket, item)}
    else
      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("dashboard_forage", "You cannot view that forage item."))
         |> push_navigate(to: ~p"/forage")}

      _error ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("dashboard_forage", "Forage item not found."))
         |> push_navigate(to: ~p"/forage")}
    end
  end

  @impl true
  def handle_event("follow", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply,
     put_flash(socket, :error, dgettext("dashboard_forage", "Sign in to follow this item."))}
  end

  def handle_event("follow", _params, socket) do
    {:ok, _subscription} =
      Notifications.follow_forage_item(socket.assigns.current_user, socket.assigns.item.id,
        cadence: :immediate
      )

    {:noreply,
     socket
     |> assign(:following?, true)
     |> put_flash(:info, dgettext("dashboard_forage", "You are following this item."))}
  end

  def handle_event("unfollow", _params, %{assigns: %{current_user: nil}} = socket) do
    {:noreply,
     put_flash(socket, :error, dgettext("dashboard_forage", "Sign in to follow this item."))}
  end

  def handle_event("unfollow", _params, socket) do
    Notifications.unsubscribe(
      socket.assigns.current_user,
      :forage_item_updates,
      socket.assigns.item.id
    )

    {:noreply,
     socket
     |> assign(:following?, false)
     |> put_flash(:info, dgettext("dashboard_forage", "You are no longer following this item."))}
  end

  @impl true
  def handle_event("edit_item", _params, socket) do
    item = socket.assigns.item

    if Forage.can_edit_item?(item && item.source_record, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:editing_item?, true)
       |> assign_item_edit_form(item_edit_changeset(item))}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_forage", "Only the item author can edit this item.")
       )}
    end
  end

  @impl true
  def handle_event("validate_item_edit", %{"forage_item_edit" => params}, socket) do
    item = socket.assigns.item

    if Forage.can_edit_item?(item && item.source_record, socket.assigns.current_user) do
      changeset =
        item.source_record
        |> Forage.change_forage_item(params)
        |> Map.put(:action, :validate)

      {:noreply,
       socket
       |> assign(:editing_item?, true)
       |> assign_item_edit_form(changeset)}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         dgettext("dashboard_forage", "Only the item author can edit this item.")
       )}
    end
  end

  @impl true
  def handle_event("update_item", %{"forage_item_edit" => params}, socket) do
    item = socket.assigns.item

    case Forage.update_forage_item(
           item && item.source_record,
           params,
           socket.assigns.current_user
         ) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_forage", "Forage item updated."))
         |> refresh_item()}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_forage", "Only the item author can edit this item.")
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:editing_item?, true)
         |> assign_item_edit_form(Map.put(changeset, :action, :validate))}
    end
  end

  @impl true
  def handle_event("cancel_item_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_item?, false)
     |> assign_item_edit_form(item_edit_changeset(socket.assigns.item))}
  end

  @impl true
  def handle_event("comment", %{"comment" => params}, socket) do
    item = socket.assigns.item

    case Forage.add_comment(item && item.source_record, params, socket.assigns.current_user) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> put_flash(:info, dgettext("dashboard_forage", "Comment added."))
         |> refresh_item()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_forage", "Sign in to comment."))}

      {:error, changeset} ->
        {:noreply, assign_comment_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  @impl true
  def handle_event("edit_comment", %{"id" => comment_id}, socket) do
    with {:ok, comment} <- find_comment(socket, comment_id),
         true <- Forage.can_edit_comment?(comment, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:editing_comment_id, comment.id)
       |> assign_edit_comment_form(Forage.change_comment(comment))}
    else
      _error ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_forage", "Only the comment author can edit this comment.")
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
         true <- Forage.can_edit_comment?(comment, socket.assigns.current_user) do
      changeset =
        comment
        |> Forage.change_comment(params)
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
           dgettext("dashboard_forage", "Only the comment author can edit this comment.")
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
         {:ok, _comment} <- Forage.update_comment(comment, params, socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, dgettext("dashboard_forage", "Comment updated."))
       |> refresh_item()}
    else
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           dgettext("dashboard_forage", "Only the comment author can edit this comment.")
         )}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:editing_comment_id, comment_id)
         |> assign_edit_comment_form(Map.put(changeset, :action, :validate))}

      _error ->
        {:noreply, put_flash(socket, :error, dgettext("dashboard_forage", "Comment not found."))}
    end
  end

  @impl true
  def handle_event("cancel_comment_edit", _params, socket) do
    {:noreply, clear_comment_edit(socket)}
  end

  def handle_event(
        "start_coding_run",
        %{
          "coding_run" => %{
            "repository_id" => repository_id,
            "objective" => objective
          }
        },
        socket
      ) do
    case socket.assigns.item do
      %{origin: origin} = item when origin in [:grafana, :github] ->
        case Flights.start_for_item(
               item,
               repository_id,
               socket.assigns.current_user,
               objective: objective,
               trigger: %{"source" => "dashboard"}
             ) do
          {:ok, _run} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               dgettext("dashboard_forage", "Flight queued. The result will appear here.")
             )
             |> assign_coding_runs(socket.assigns.item)}

          {:error, :already_running} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext(
                 "dashboard_forage",
                 "A Flight is already active for that repository."
               )
             )}

          {:error, :not_configured} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("dashboard_forage", "The Flight runner is not configured.")
             )}

          {:error, _reason} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               dgettext("dashboard_forage", "The Flight could not be queued.")
             )}
        end

      _item ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:coding_run_updated, _coding_run_id}, socket) do
    {:noreply, assign_coding_runs(socket, socket.assigns.item)}
  end

  defp assign_item(socket, item) do
    socket
    |> assign(
      :page_title,
      dgettext("dashboard_forage", "%{title} · %{product}",
        title: item.title,
        product: socket.assigns.product_name
      )
    )
    |> assign(OpenGraph.assigns(open_graph(item)))
    |> assign(:item, item)
    |> assign(
      :following?,
      Notifications.subscribed?(socket.assigns.current_user, :forage_item_updates, item.id)
    )
    |> assign(
      :can_edit_item?,
      Forage.can_edit_item?(item.source_record, socket.assigns.current_user)
    )
    |> assign(
      :can_comment_item?,
      Forage.can_comment_item?(item.source_record, socket.assigns.current_user)
    )
    |> assign(:editing_item?, false)
    |> assign_item_edit_form(item_edit_changeset(item))
    |> assign_comment_form(Forage.change_comment())
    |> assign(:editing_comment_id, nil)
    |> assign_edit_comment_form(Forage.change_comment())
    |> assign_coding_runs(item)
  end

  defp assign_coding_runs(socket, %{origin: origin} = item) when origin in [:grafana, :github] do
    repositories = CodingRuns.repositories_for_item(item)
    runs = CodingRuns.list_for_item(item.id)
    runner_enabled? = CodingRuns.enabled?()
    active? = Enum.any?(runs, &(&1.status in [:queued, :running]))
    selected_repository_id = repositories |> List.first() |> then(&(&1 && &1.id))

    socket
    |> assign(:coding_runs, runs)
    |> assign(:coding_repositories, repositories)
    |> assign(:coding_runner_enabled?, runner_enabled?)
    |> assign(
      :can_start_coding_run?,
      runner_enabled? and repositories != [] and !active?
    )
    |> assign(
      :coding_run_form,
      to_form(
        %{"repository_id" => selected_repository_id || "", "objective" => "investigate"},
        as: :coding_run
      )
    )
  end

  defp assign_coding_runs(socket, _item) do
    socket
    |> assign(:coding_runs, [])
    |> assign(:coding_repositories, [])
    |> assign(:coding_runner_enabled?, false)
    |> assign(:can_start_coding_run?, false)
  end

  defp refresh_item(%{assigns: %{item: %{id: item_id}}} = socket) do
    case Forage.get_item_for_user(item_id, socket.assigns.current_user,
           fetch_github_comments?: true
         ) do
      {:ok, item} -> assign_item(socket, item)
      {:error, _reason} -> socket
    end
  end

  defp item_edit_changeset(%{source_record: %FeatureRequest{} = item}) do
    Forage.change_forage_item(item)
  end

  defp item_edit_changeset(_item), do: Forage.change_forage_item()

  defp assign_item_edit_form(socket, changeset) do
    assign(
      socket,
      :item_edit_form,
      to_form(interpolate_errors(changeset), as: :forage_item_edit)
    )
  end

  defp assign_comment_form(socket, changeset) do
    assign(socket, :comment_form, to_form(interpolate_errors(changeset), as: :comment))
  end

  defp assign_edit_comment_form(socket, changeset) do
    assign(socket, :edit_comment_form, to_form(interpolate_errors(changeset), as: :comment_edit))
  end

  defp clear_comment_edit(socket) do
    socket
    |> assign(:editing_comment_id, nil)
    |> assign_edit_comment_form(Forage.change_comment())
  end

  defp find_comment(%{assigns: %{item: %{comments: comments}}}, comment_id)
       when is_list(comments) do
    case Enum.find(comments, &(&1.id == comment_id)) do
      nil -> :error
      comment -> {:ok, comment}
    end
  end

  defp find_comment(_socket, _comment_id), do: :error

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

  defp open_graph_id(%{id: "manual:" <> id}), do: "forage-item-manual-#{id}"
  defp open_graph_id(%{id: "github_issue:" <> id}), do: "forage-item-github-issue-#{id}"
  defp open_graph_id(%{id: "grafana_alert:" <> id}), do: "forage-item-grafana-alert-#{id}"

  defp item_description(%{body: body}) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 220)
  end

  defp item_description(item) do
    dgettext("dashboard_forage", "%{type} from %{source}.",
      type: Forage.item_type_label(item.type),
      source: item.source_label || "Hive"
    )
  end

  defp comments_highlight(%{comments: comments}) when is_list(comments) do
    count = length(comments)

    if count == 1 do
      dgettext("dashboard_forage", "1 comment")
    else
      dgettext("dashboard_forage", "%{count} comments", count: count)
    end
  end

  defp comments_highlight(_item), do: nil

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
      <ForageComponents.item_detail
        :if={@item}
        item={@item}
        following?={@following?}
        can_create_spec?={@can_create_spec?}
        can_edit_item?={@can_edit_item?}
        can_comment_item?={@can_comment_item?}
        editing_item?={@editing_item?}
        item_edit_form={@item_edit_form}
        comment_form={@comment_form}
        edit_comment_form={@edit_comment_form}
        editing_comment_id={@editing_comment_id}
        signed_in?={@signed_in?}
        current_path={@current_path}
        current_user={@current_user}
        coding_runs={@coding_runs}
        coding_repositories={@coding_repositories}
        coding_runner_enabled?={@coding_runner_enabled?}
        can_start_coding_run?={@can_start_coding_run?}
        coding_run_form={@coding_run_form}
      />
    </Layouts.dashboard>
    """
  end
end
