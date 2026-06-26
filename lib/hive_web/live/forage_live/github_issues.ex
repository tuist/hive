defmodule HiveWeb.ForageLive.GitHubIssues do
  @moduledoc """
  Lists open GitHub issues across every repository connected to a domain
  the current user is allowed to see. Issues are served from the cache
  populated by `Hive.Forage.GitHubIssueSyncer`; filters live in the URL.
  """

  use HiveWeb, :live_view

  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.Domains.GitHubRepository
  alias HiveWeb.ForageComponents
  alias HiveWeb.Layouts
  alias HiveWeb.OpenGraph
  alias Noora.Filter.Operations

  def open_graph(source, stats) do
    %{
      description: source.description,
      section_label: dgettext("dashboard_forage", "Forage"),
      highlights: [
        dgettext("dashboard_forage", "%{count} %{state}",
          count: stats.total,
          state: stats.state_label
        ),
        repository_highlight(stats.repositories),
        domain_highlight(stats.domains)
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
      pairs = Forage.accessible_domains_with_repositories(socket.assigns.current_user)
      available_filters = available_filters(pairs)

      {:ok,
       socket
       |> assign(
         :page_title,
         dgettext("dashboard_forage", "%{source} · %{product}",
           source: source.label,
           product: socket.assigns.product_name
         )
       )
       |> assign(:source, source)
       |> assign(:pairs, pairs)
       |> assign(:available_filters, available_filters)
       |> assign(:active_filters, [])
       |> assign(:uri, URI.parse(source.path))
       |> assign(:entries, [])
       |> assign(:stats, blank_stats())
       |> assign(:atom_feed, %{
         title: dgettext("dashboard_forage", "Hive · GitHub issues"),
         atom_href: "/forage/github-issues/atom.xml",
         rss_href: "/forage/github-issues/rss.xml"
       })
       |> assign(OpenGraph.assigns(open_graph(source, blank_stats())))}
    else
      {:ok, redirect(socket, to: ~p"/forage/feature-requests")}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    merged_params = default_filter_params(params)

    if merged_params == params do
      apply_filters(merged_params, URI.parse(uri), socket)
    else
      {:noreply, push_patch(socket, to: ~p"/forage/github-issues?#{merged_params}")}
    end
  end

  defp apply_filters(params, uri, socket) do
    active_filters =
      Operations.decode_filters_from_query(params, socket.assigns.available_filters)

    entries =
      Forage.list_github_issues_for_user(
        socket.assigns.current_user,
        state: filter_value(active_filters, "state"),
        domain_id: filter_value(active_filters, "domain"),
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
    domains =
      pairs
      |> Enum.map(fn {domain, _repo} -> domain end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.name)

    repositories =
      pairs
      |> Enum.map(fn {_domain, repo} -> repo end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&GitHubRepository.full_name/1)

    [
      %Noora.Filter.Filter{
        id: "state",
        field: :state,
        display_name: dgettext("dashboard_forage", "State"),
        type: :option,
        options: GitHubIssue.states(),
        options_display_names: Map.new(GitHubIssue.states(), &{&1, state_label(&1)}),
        operator: :==,
        value: :open
      },
      %Noora.Filter.Filter{
        id: "domain",
        field: :domain_id,
        display_name: dgettext("dashboard_forage", "Domain"),
        type: :option,
        options: Enum.map(domains, & &1.id),
        options_display_names: Map.new(domains, &{&1.id, &1.name}),
        operator: :==,
        value: nil
      },
      %Noora.Filter.Filter{
        id: "repository",
        field: :repository_id,
        display_name: dgettext("dashboard_forage", "Repository"),
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
      repositories:
        entries |> Enum.map(fn {repo, _i, _ms} -> repo.id end) |> Enum.uniq() |> length(),
      domains:
        entries
        |> Enum.flat_map(fn {_repo, _issue, domains} -> Enum.map(domains, & &1.id) end)
        |> Enum.uniq()
        |> length(),
      state_label: state_label_plural(state)
    }
  end

  defp blank_stats,
    do: %{
      total: 0,
      repositories: 0,
      domains: 0,
      state_label: dgettext("dashboard_forage", "open issues")
    }

  defp state_label(:open), do: dgettext("dashboard_forage", "Open")
  defp state_label(:closed), do: dgettext("dashboard_forage", "Closed")

  defp state_label_plural(:open), do: dgettext("dashboard_forage", "open issues")
  defp state_label_plural(:closed), do: dgettext("dashboard_forage", "closed issues")

  defp repository_highlight(1), do: dgettext("dashboard_forage", "1 repository")

  defp repository_highlight(count),
    do: dgettext("dashboard_forage", "%{count} repositories", count: count)

  defp domain_highlight(1), do: dgettext("dashboard_forage", "1 domain")
  defp domain_highlight(count), do: dgettext("dashboard_forage", "%{count} domains", count: count)
end
