defmodule HiveWeb.ForageLive.GitHubIssues do
  @moduledoc """
  Lists open GitHub issues across every repository connected to a product
  the current user is allowed to see. Issues are served from the cache
  populated by `Hive.Forage.GitHubIssueSyncer`; filters live in the URL.
  """

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.Products.GitHubRepository
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias Noora.Filter.Operations

  def open_graph(source, stats) do
    %{
      description: source.description,
      eyebrow: "Forage",
      highlights: [
        "#{stats.total} #{stats.state_label}",
        "#{stats.repositories} #{pluralize(stats.repositories, "repository", "repositories")}",
        "#{stats.products} #{pluralize(stats.products, "product", "products")}"
      ],
      id: "forage-github-issues",
      path: source.path,
      title: source.label
    }
  end

  @impl true
  def mount(_params, _session, socket) do
    source = Forage.get_source!(:github_issues)

    if Forage.can_access?(source, socket.assigns.current_user) do
      pairs = Forage.accessible_products_with_repositories(socket.assigns.current_user)
      available_filters = available_filters(pairs)

      {:ok,
       socket
       |> assign(:page_title, "#{source.label} · #{socket.assigns.product_name}")
       |> assign(:source, source)
       |> assign(:pairs, pairs)
       |> assign(:available_filters, available_filters)
       |> assign(:active_filters, [])
       |> assign(:uri, URI.parse(source.path))
       |> assign(:entries, [])
       |> assign(:stats, %{total: 0, repositories: 0, products: 0, state_label: "open issues"})
       |> assign(OpenGraph.assigns(open_graph(source, blank_stats())))}
    else
      {:ok, redirect(socket, to: ~p"/forage/feature-requests")}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    params = default_filter_params(params)
    uri = URI.parse(uri)

    active_filters =
      Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    entries =
      Forage.list_github_issues_for_user(
        socket.assigns.current_user,
        state: filter_value(active_filters, "state"),
        product_id: filter_value(active_filters, "product"),
        repository_id: filter_value(active_filters, "repository")
      )

    stats = stats(entries, active_filters)

    {:noreply,
     socket
     |> assign(:uri, %{uri | query: URI.encode_query(params)})
     |> assign(:active_filters, active_filters)
     |> assign(:entries, entries)
     |> assign(:stats, stats)
     |> assign(OpenGraph.assigns(open_graph(socket.assigns.source, stats)))}
  end

  @impl true
  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Operations.add_filter_to_query(filter_id, socket)
    {:noreply, push_patch(socket, to: ~p"/forage/github-issues?#{params}")}
  end

  @impl true
  def handle_event("update_filter", params, socket) do
    params = Operations.update_filters_in_query(params, socket)
    {:noreply, push_patch(socket, to: ~p"/forage/github-issues?#{params}")}
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
      settings_enabled?={@settings_enabled?}
      csrf_token={@csrf_token}
      current_path={@current_path}
      forage_sources={@forage_sources}
    >
      <ForageComponents.github_issues
        source={@source}
        signed_in?={@signed_in?}
        entries={@entries}
        stats={@stats}
        available_filters={@available_filters}
        active_filters={@active_filters}
      />
    </Layouts.dashboard>
    """
  end

  defp available_filters(pairs) do
    products =
      pairs
      |> Enum.map(fn {product, _repo} -> product end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.name)

    repositories =
      pairs
      |> Enum.map(fn {_product, repo} -> repo end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&GitHubRepository.full_name/1)

    [
      %Noora.Filter.Filter{
        id: "state",
        field: :state,
        display_name: "State",
        type: :option,
        options: GitHubIssue.states(),
        options_display_names: Map.new(GitHubIssue.states(), &{&1, state_label(&1)}),
        operator: :==,
        value: :open
      },
      %Noora.Filter.Filter{
        id: "product",
        field: :product_id,
        display_name: "Product",
        type: :option,
        options: Enum.map(products, & &1.id),
        options_display_names: Map.new(products, &{&1.id, &1.name}),
        operator: :==,
        value: nil
      },
      %Noora.Filter.Filter{
        id: "repository",
        field: :repository_id,
        display_name: "Repository",
        type: :option,
        options: Enum.map(repositories, & &1.id),
        options_display_names: Map.new(repositories, &{&1.id, GitHubRepository.full_name(&1)}),
        operator: :==,
        value: nil
      }
    ]
  end

  defp default_filter_params(%{"filter_state_op" => _op, "filter_state_val" => _val} = params),
    do: params

  defp default_filter_params(params) do
    Map.merge(params, %{"filter_state_op" => "==", "filter_state_val" => "open"})
  end

  defp filter_value(active_filters, id) do
    active_filters
    |> Enum.find(&(&1.id == id))
    |> case do
      %{operator: :==, value: value} -> value
      _filter -> nil
    end
  end

  defp stats(entries, active_filters) do
    state = filter_value(active_filters, "state") || :open

    %{
      total: length(entries),
      repositories: entries |> Enum.map(fn {_p, r, _i} -> r.id end) |> Enum.uniq() |> length(),
      products: entries |> Enum.map(fn {p, _r, _i} -> p.id end) |> Enum.uniq() |> length(),
      state_label: state_label_plural(state)
    }
  end

  defp blank_stats, do: %{total: 0, repositories: 0, products: 0, state_label: "open issues"}

  defp state_label(:open), do: "Open"
  defp state_label(:closed), do: "Closed"

  defp state_label_plural(:open), do: "open issues"
  defp state_label_plural(:closed), do: "closed issues"

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural
end
