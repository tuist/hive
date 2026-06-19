defmodule HiveWeb.ForageLive.Index do
  @moduledoc false

  use HiveWeb, :live_view

  alias Hive.Forage.FeatureRequest
  alias Hive.Forage
  alias Hive.Meadows.GitHubRepository
  alias Hive.Specs
  alias HiveWeb.ForageComponents
  alias HiveWeb.ForageLive.Show
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias HiveWeb.Utilities.Query
  alias Noora.Filter
  alias Noora.Filter.Operations

  @page_size 10

  def open_graph(stats) do
    %{
      description:
        "A unified queue for feature requests, bug reports, feedback, GitHub issues, and Grafana alerts.",
      eyebrow: "Forage",
      highlights: [
        "#{stats.total} items",
        "#{stats.open} open signals",
        "#{stats.meadows} meadows"
      ],
      id: "forage",
      path: "/forage",
      title: "Forage"
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Forage · #{socket.assigns.product_name}")
     |> assign(:available_filters, [])
     |> assign(:active_filters, [])
     |> assign(:items, [])
     |> assign(:meta, %{total_count: 0, total_pages: 1, current_page: 1, page_size: @page_size})
     |> assign(:stats, %{total: 0, open: 0, meadows: 0})
     |> assign(:uri, URI.parse("/forage"))
     |> assign(:query, "")
     |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
     |> assign(:can_create_spec?, Specs.can_create?(socket.assigns.current_user))
     |> assign(:selected_item, nil)
     |> assign(:selected_item_error, nil)
     |> assign(:can_edit_selected_item?, false)
     |> assign(:can_comment_selected_item?, false)
     |> assign(:editing_item?, false)
     |> assign_item_edit_form(Forage.change_forage_item())
     |> assign_comment_form(Forage.change_comment())
     |> assign(:editing_comment_id, nil)
     |> assign_edit_comment_form(Forage.change_comment())
     |> assign(:atom_feed, %{
       title: "Hive · Forage",
       atom_href: "/forage/atom.xml",
       rss_href: "/forage/rss.xml"
     })
     |> assign(OpenGraph.assigns(open_graph(%{total: 0, open: 0, meadows: 0})))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    case legacy_type(socket.assigns.live_action) do
      nil ->
        maybe_redirect_to_item(params, uri, socket)

      type ->
        params =
          params
          |> Map.put_new("filter_type_op", "==")
          |> Map.put_new("filter_type_val", Atom.to_string(type))

        {:noreply, push_patch(socket, to: ~p"/forage?#{params}")}
    end
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/forage?#{forage_query_params(query, socket.assigns.active_filters)}",
       replace: true
     )}
  end

  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Operations.add_filter_to_query(filter_id, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/forage?#{updated_params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  @impl true
  def handle_event("update_filter", params, socket) do
    updated_params =
      socket
      |> current_query_params()
      |> Map.delete("page")
      |> then(&Operations.update_filters_in_query(params, socket, &1))

    {:noreply,
     socket
     |> push_patch(to: ~p"/forage?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  @impl true
  def handle_event("edit_item", _params, socket) do
    item = socket.assigns.selected_item

    if Forage.can_edit_item?(item && item.source_record, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:editing_item?, true)
       |> assign_item_edit_form(item_edit_changeset(item))}
    else
      {:noreply, put_flash(socket, :error, "Only the item author can edit this item.")}
    end
  end

  @impl true
  def handle_event("validate_item_edit", %{"forage_item_edit" => params}, socket) do
    item = socket.assigns.selected_item

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
      {:noreply, put_flash(socket, :error, "Only the item author can edit this item.")}
    end
  end

  @impl true
  def handle_event("update_item", %{"forage_item_edit" => params}, socket) do
    item = socket.assigns.selected_item

    case Forage.update_forage_item(
           item && item.source_record,
           params,
           socket.assigns.current_user
         ) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Forage item updated.")
         |> refresh_from_current_params()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the item author can edit this item.")}

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
     |> assign_item_edit_form(item_edit_changeset(socket.assigns.selected_item))}
  end

  @impl true
  def handle_event("comment", %{"comment" => params}, socket) do
    item = socket.assigns.selected_item

    case Forage.add_comment(item && item.source_record, params, socket.assigns.current_user) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Comment added.")
         |> refresh_from_current_params()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Sign in to comment.")}

      {:error, changeset} ->
        {:noreply, assign_comment_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  @impl true
  def handle_event("edit_comment", %{"id" => comment_id}, socket) do
    with {:ok, comment} <- find_selected_comment(socket, comment_id),
         true <- Forage.can_edit_comment?(comment, socket.assigns.current_user) do
      {:noreply,
       socket
       |> assign(:editing_comment_id, comment.id)
       |> assign_edit_comment_form(Forage.change_comment(comment))}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "Only the comment author can edit this comment.")}
    end
  end

  @impl true
  def handle_event(
        "validate_comment_edit",
        %{"comment_edit" => params, "comment_id" => comment_id},
        socket
      ) do
    with {:ok, comment} <- find_selected_comment(socket, comment_id),
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
        {:noreply, put_flash(socket, :error, "Only the comment author can edit this comment.")}
    end
  end

  @impl true
  def handle_event(
        "update_comment",
        %{"comment_edit" => params, "comment_id" => comment_id},
        socket
      ) do
    with {:ok, comment} <- find_selected_comment(socket, comment_id),
         {:ok, _comment} <- Forage.update_comment(comment, params, socket.assigns.current_user) do
      {:noreply,
       socket
       |> put_flash(:info, "Comment updated.")
       |> refresh_from_current_params()}
    else
      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the comment author can edit this comment.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:editing_comment_id, comment_id)
         |> assign_edit_comment_form(Map.put(changeset, :action, :validate))}

      _error ->
        {:noreply, put_flash(socket, :error, "Comment not found.")}
    end
  end

  @impl true
  def handle_event("cancel_comment_edit", _params, socket) do
    {:noreply, clear_comment_edit(socket)}
  end

  defp apply_params(params, uri, socket) do
    {:noreply, assign_params(socket, params, uri)}
  end

  defp maybe_redirect_to_item(%{"item" => item_id}, _uri, socket) when is_binary(item_id) do
    {:noreply, push_navigate(socket, to: Show.item_path_from_id!(item_id))}
  end

  defp maybe_redirect_to_item(params, uri, socket), do: apply_params(params, uri, socket)

  defp assign_params(socket, params, uri) do
    available_filters = define_filters(socket.assigns.current_user)
    page = Query.parse_page(params["page"])
    query = params["q"] || ""
    active_filters = Operations.decode_filters_from_query(params, available_filters)
    base_opts = list_opts(query, active_filters)

    {all_items, _all_meta} =
      Forage.list_forage_items_for_user(
        socket.assigns.current_user,
        base_opts ++ [page_size: :all]
      )

    {items, meta} =
      Forage.list_forage_items_for_user(
        socket.assigns.current_user,
        base_opts ++ [page: page, page_size: @page_size]
      )

    stats = stats(all_items, meta)
    query_params = Query.query_params(uri)

    socket
    |> assign(:uri, uri_from_query_params(query_params))
    |> assign(:available_filters, available_filters)
    |> assign(:active_filters, active_filters)
    |> assign(:items, items)
    |> assign(:meta, meta)
    |> assign(:stats, stats)
    |> assign(:query, query)
    |> assign(:search_form, to_form(%{"query" => query}, as: :search))
    |> assign(OpenGraph.assigns(open_graph(stats)))
    |> assign_selected_item(params["item"])
  end

  defp list_opts(query, active_filters) do
    [
      query: Query.present_string(query),
      type: filter_value(active_filters, "type"),
      status: filter_value(active_filters, "status"),
      meadow_id: filter_value(active_filters, "meadow"),
      repository_id: filter_value(active_filters, "repository")
    ]
  end

  defp filter_value(active_filters, id) do
    active_filters
    |> Enum.find(&(&1.id == id))
    |> case do
      %{operator: :==, value: value} -> value
      _filter -> nil
    end
  end

  defp stats(items, meta) do
    %{
      total: meta.total_count,
      open: Enum.count(items, &(&1.status in [:open, :firing])),
      meadows:
        items
        |> Enum.flat_map(& &1.meadows)
        |> Enum.map(& &1.id)
        |> Enum.uniq()
        |> length()
    }
  end

  defp page_link(uri, page) do
    query_path(Query.put(uri.query, "page", Integer.to_string(page)))
  end

  defp item_link(_uri, item), do: Show.item_path(item)

  defp forage_query_params(query, active_filters) do
    active_filters
    |> Operations.encode_filters_to_query()
    |> Query.put_present("q", Query.present_string(query))
  end

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp uri_from_query_params(params) do
    case URI.encode_query(params) do
      "" -> URI.parse("")
      query -> URI.parse("?" <> query)
    end
  end

  defp query_path(nil), do: "/forage"
  defp query_path(""), do: "/forage"
  defp query_path(query), do: "/forage?#{query}"

  defp assign_selected_item(socket, nil), do: clear_selected_item(socket)
  defp assign_selected_item(socket, ""), do: clear_selected_item(socket)

  defp assign_selected_item(socket, item_id) do
    case Forage.get_item_for_user(item_id, socket.assigns.current_user,
           fetch_github_comments?: true
         ) do
      {:ok, item} ->
        socket
        |> assign(:selected_item, item)
        |> assign(:selected_item_error, nil)
        |> assign(
          :can_edit_selected_item?,
          Forage.can_edit_item?(item.source_record, socket.assigns.current_user)
        )
        |> assign(
          :can_comment_selected_item?,
          Forage.can_comment_item?(item.source_record, socket.assigns.current_user)
        )
        |> assign(:editing_item?, false)
        |> assign_item_edit_form(item_edit_changeset(item))
        |> assign_comment_form(Forage.change_comment())
        |> assign(:editing_comment_id, nil)
        |> assign_edit_comment_form(Forage.change_comment())

      {:error, reason} ->
        socket
        |> clear_selected_item()
        |> assign(:selected_item_error, reason)
        |> put_flash(:error, item_error_message(reason))
    end
  end

  defp clear_selected_item(socket) do
    socket
    |> assign(:selected_item, nil)
    |> assign(:selected_item_error, nil)
    |> assign(:can_edit_selected_item?, false)
    |> assign(:can_comment_selected_item?, false)
    |> assign(:editing_item?, false)
    |> assign_item_edit_form(Forage.change_forage_item())
    |> assign_comment_form(Forage.change_comment())
    |> assign(:editing_comment_id, nil)
    |> assign_edit_comment_form(Forage.change_comment())
  end

  defp refresh_from_current_params(socket) do
    params = current_query_params(socket)
    assign_params(socket, params, URI.to_string(socket.assigns.uri))
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

  defp find_selected_comment(%{assigns: %{selected_item: %{comments: comments}}}, comment_id)
       when is_list(comments) do
    case Enum.find(comments, &(&1.id == comment_id)) do
      nil -> :error
      comment -> {:ok, comment}
    end
  end

  defp find_selected_comment(_socket, _comment_id), do: :error

  defp item_error_message(:unauthorized), do: "You cannot view that forage item."
  defp item_error_message(_reason), do: "Forage item not found."

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

  defp define_filters(user) do
    options = Forage.forage_item_filter_options(user)

    [
      option_filter("type", "Type", options.item_types, &Forage.item_type_label/1,
        searchable: false
      ),
      option_filter("status", "Status", options.statuses, &Forage.item_status_label/1,
        searchable: false
      ),
      option_filter("meadow", "Meadow", options.meadows, & &1.name, searchable: true),
      option_filter(
        "repository",
        "Repository",
        options.repositories,
        &GitHubRepository.full_name/1,
        searchable: true
      )
    ]
    |> Enum.reject(&Enum.empty?(&1.options))
  end

  defp option_filter(id, display_name, options, formatter, opts) do
    values =
      options
      |> Enum.map(&filter_option_value/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    %Filter.Filter{
      id: id,
      display_name: display_name,
      type: :option,
      options: values,
      options_display_names: Map.new(options, &{filter_option_value(&1), formatter.(&1)}),
      operator: :==,
      searchable: Keyword.get(opts, :searchable, false),
      value: nil
    }
  end

  defp filter_option_value(%{id: id}), do: id
  defp filter_option_value(value), do: value

  defp legacy_type(:feature_requests), do: :feature_request
  defp legacy_type(:bug_reports), do: :bug_report
  defp legacy_type(:feedback), do: :feedback
  defp legacy_type(:github_issues), do: :github_issue
  defp legacy_type(:grafana_alerts), do: :grafana_alert
  defp legacy_type(_action), do: nil

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
      <ForageComponents.items
        items={@items}
        stats={@stats}
        meta={@meta}
        search_form={@search_form}
        available_filters={@available_filters}
        active_filters={@active_filters}
        signed_in?={@signed_in?}
        can_create_spec?={@can_create_spec?}
        page_link={fn page -> page_link(@uri, page) end}
        item_link={fn item -> item_link(@uri, item) end}
      />
    </Layouts.dashboard>
    """
  end
end
