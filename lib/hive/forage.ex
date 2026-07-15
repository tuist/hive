defmodule Hive.Forage do
  @moduledoc """
  Collects sources that can feed Hive with workable pieces of work.
  """

  use Gettext, backend: HiveWeb.Gettext

  import Ecto.Query

  alias Hive.Accounts.User
  alias Hive.Auth
  alias Hive.Domains.Domain
  alias Hive.Domains.GitHubRepository
  alias Hive.Forage.Comment
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueClassification
  alias Hive.Forage.GitHubIssueClassificationWorker
  alias Hive.Forage.Grafana
  alias Hive.Forage.Item
  alias Hive.Forage.Policy
  alias Hive.GitHub.Issues
  alias Hive.Repo

  @default_item_page_size 20

  @source_ids [:feature_requests, :bug_reports, :feedback, :github_issues, :grafana_alerts]

  def sources, do: Enum.map(@source_ids, &source/1)

  def visible_sources(user) do
    Enum.filter(sources(), &can_access?(&1, user))
  end

  def get_source!(id) do
    Enum.find(sources(), &(&1.id == id)) || raise ArgumentError, "unknown forage source: #{id}"
  end

  defp source(:feature_requests) do
    %{
      id: :feature_requests,
      label: dgettext("dashboard_forage", "Feature requests"),
      description:
        dgettext("dashboard_forage", "Public domain ideas submitted by authenticated users."),
      icon: "bulb",
      path: "/forage/feature-requests",
      visibility: :public,
      creatable?: true
    }
  end

  defp source(:bug_reports) do
    %{
      id: :bug_reports,
      label: dgettext("dashboard_forage", "Bug reports"),
      description:
        dgettext("dashboard_forage", "Public defects that should become actionable work."),
      icon: "file_alert",
      path: "/forage/bug-reports",
      visibility: :public,
      creatable?: true
    }
  end

  defp source(:feedback) do
    %{
      id: :feedback,
      label: dgettext("dashboard_forage", "Feedback"),
      description:
        dgettext("dashboard_forage", "Public feedback that helps shape the domain direction."),
      icon: "message_circle",
      path: "/forage/feedback",
      visibility: :public,
      creatable?: true
    }
  end

  defp source(:github_issues) do
    %{
      id: :github_issues,
      label: dgettext("dashboard_forage", "GitHub issues"),
      description:
        dgettext(
          "dashboard_forage",
          "Open issues from the GitHub repositories connected to your projects."
        ),
      icon: "brand_github",
      path: "/forage/github-issues",
      visibility: :per_domain,
      creatable?: false
    }
  end

  defp source(:grafana_alerts) do
    %{
      id: :grafana_alerts,
      label: dgettext("dashboard_forage", "Grafana alerts"),
      description:
        dgettext("dashboard_forage", "Operational signals visible only to organization members."),
      icon: "bell",
      path: "/forage/grafana-alerts",
      visibility: :organization,
      creatable?: false
    }
  end

  def can_access?(%{visibility: :per_domain}, user) do
    Auth.member?(user) or accessible_domains_with_repositories(user) != []
  end

  def can_access?(source, user) do
    Policy.authorize?(:forage_source_read, user, source)
  end

  def can_create?(source, user) do
    Policy.authorize?(:forage_source_create, user, source)
  end

  def can_view_item?(%FeatureRequest{visibility: :organization}, user), do: Auth.member?(user)
  def can_view_item?(%FeatureRequest{}, _user), do: true

  def can_edit_item?(%FeatureRequest{user_id: user_id}, %User{id: user_id})
      when is_binary(user_id),
      do: true

  def can_edit_item?(_item, _user), do: false

  def can_comment_item?(%FeatureRequest{} = item, %User{} = user), do: can_view_item?(item, user)
  def can_comment_item?(_item, _user), do: false

  def can_edit_comment?(%Comment{user_id: user_id}, %User{id: user_id}) when is_binary(user_id),
    do: true

  def can_edit_comment?(_comment, _user), do: false

  def item_types do
    FeatureRequest.types() ++ [:github_issue, :grafana_alert]
  end

  def manual_item_types, do: FeatureRequest.types()

  def item_statuses do
    [:open, :planned, :closed, :firing, :resolved]
  end

  def item_type_label(:feature_request), do: dgettext("dashboard_forage", "Feature request")
  def item_type_label(:bug_report), do: dgettext("dashboard_forage", "Bug report")
  def item_type_label(:feedback), do: dgettext("dashboard_forage", "Feedback")
  def item_type_label(:github_issue), do: dgettext("dashboard_forage", "GitHub issue")
  def item_type_label(:grafana_alert), do: dgettext("dashboard_forage", "Grafana alert")

  def item_type_label(type),
    do: type |> to_string() |> String.replace("_", " ") |> String.capitalize()

  def item_status_label(:open), do: dgettext("dashboard_forage", "Open")
  def item_status_label(:planned), do: dgettext("dashboard_forage", "Planned")
  def item_status_label(:closed), do: dgettext("dashboard_forage", "Closed")
  def item_status_label(:firing), do: dgettext("dashboard_forage", "Firing")
  def item_status_label(:resolved), do: dgettext("dashboard_forage", "Resolved")

  def item_status_label(status),
    do: status |> to_string() |> String.replace("_", " ") |> String.capitalize()

  def item_status_color(:open), do: "information"
  def item_status_color(:planned), do: "attention"
  def item_status_color(:closed), do: "neutral"
  def item_status_color(:firing), do: "attention"
  def item_status_color(:resolved), do: "success"
  def item_status_color(_status), do: "neutral"

  def forage_item_filter_options(user) do
    pairs = accessible_domains_with_repositories(user)

    repositories =
      pairs
      |> Enum.map(fn {_domain, repository} -> repository end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&GitHubRepository.full_name/1)

    domains =
      (Enum.map(pairs, fn {domain, _repository} -> domain end) ++ grafana_filter_domains(user))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.name)

    %{
      item_types: item_types(),
      statuses: item_statuses(),
      domains: domains,
      repositories: repositories
    }
  end

  def list_forage_items_for_user(user, opts \\ []) do
    opts = normalize_item_opts(opts)

    items =
      manual_item_entries(user)
      |> Kernel.++(github_issue_item_entries(user))
      |> Kernel.++(grafana_alert_item_entries(user))
      |> filter_items(opts)
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

    paginate_items(items, opts.page, opts.page_size)
  end

  def get_item_for_user(item_id, user, opts \\ [])

  def get_item_for_user("manual:" <> id, user, _opts) do
    case get_manual_item(id) do
      nil ->
        {:error, :not_found}

      %FeatureRequest{} = item ->
        if can_view_item?(item, user) do
          {:ok, manual_item_entry(item)}
        else
          {:error, :unauthorized}
        end
    end
  end

  def get_item_for_user("github_issue:" <> id, user, opts) do
    user
    |> list_github_issues_for_user(state: nil)
    |> Enum.find(fn {_repository, issue, _domains} -> issue.id == id end)
    |> case do
      nil ->
        {:error, :not_found}

      {repository, issue, domains} ->
        {:ok, github_issue_item_entry(repository, issue, domains, opts)}
    end
  end

  def get_item_for_user("grafana_alert:" <> id, user, _opts) do
    source = get_source!(:grafana_alerts)

    if can_access?(source, user) do
      list_grafana_alerts()
      |> Enum.find(&(&1.id == id))
      |> case do
        nil -> {:error, :not_found}
        alert -> {:ok, grafana_alert_item_entry(alert)}
      end
    else
      {:error, :unauthorized}
    end
  end

  def get_item_for_user(_item_id, _user, _opts), do: {:error, :not_found}

  @doc """
  Returns `{domain, repository}` tuples that the user is allowed to see.
  Effective visibility is the most restrictive of the two: a private
  repository hides the pair from anyone outside the organization, even if
  the domain itself is public.
  """
  def accessible_domains_with_repositories(user) do
    Domain
    |> preload(projects: :github_repositories)
    |> Repo.all()
    |> Enum.flat_map(fn domain ->
      repositories =
        domain.projects
        |> Enum.flat_map(& &1.github_repositories)
        |> Enum.uniq_by(& &1.id)

      Enum.map(repositories, &{domain, &1})
    end)
    |> Enum.filter(fn {domain, repository} -> accessible_pair?(domain, repository, user) end)
  end

  defp accessible_pair?(domain, repository, user) do
    case effective_visibility(domain, repository) do
      :public -> true
      :private -> Auth.member?(user)
    end
  end

  defp effective_visibility(%{visibility: :private}, _repository), do: :private
  defp effective_visibility(_domain, %{visibility: :private}), do: :private
  defp effective_visibility(_domain, _repository), do: :public

  def list_feature_requests do
    list_manual_items(type: :feature_request)
  end

  def list_manual_items(opts \\ []) do
    type = Keyword.get(opts, :type)

    FeatureRequest
    |> maybe_filter_by_manual_type(type)
    |> order_by([feature_request], desc: feature_request.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  defp maybe_filter_by_manual_type(query, nil), do: query

  defp maybe_filter_by_manual_type(query, type)
       when type in [:feature_request, :bug_report, :feedback] do
    where(query, [feature_request], feature_request.type == ^type)
  end

  defp maybe_filter_by_manual_type(query, _type), do: query

  def get_feature_request!(id) do
    FeatureRequest
    |> preload(:user)
    |> Repo.get!(id)
  end

  def change_feature_request(feature_request \\ %FeatureRequest{}, attrs \\ %{}) do
    FeatureRequest.changeset(feature_request, force_item_type(attrs, :feature_request))
  end

  def change_forage_item(feature_request \\ %FeatureRequest{}, attrs \\ %{}) do
    if is_nil(feature_request.id) do
      FeatureRequest.changeset(feature_request, attrs)
    else
      FeatureRequest.update_changeset(feature_request, attrs)
    end
  end

  def create_feature_request(attrs, %User{} = user) do
    attrs
    |> force_item_type(:feature_request)
    |> create_forage_item(user)
  end

  def create_forage_item(attrs, %User{} = user) do
    %FeatureRequest{}
    |> FeatureRequest.changeset(attrs)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
    |> case do
      {:ok, feature_request} ->
        Hive.Domains.schedule_evolution()
        {:ok, feature_request}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_forage_item(%FeatureRequest{} = item, attrs, %User{} = user) do
    if can_edit_item?(item, user) do
      item
      |> FeatureRequest.update_changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, item} ->
          Hive.Domains.schedule_evolution()
          {:ok, item}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  def update_forage_item(_item, _attrs, _user), do: {:error, :unauthorized}

  def change_comment(comment \\ %Comment{}, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end

  def get_comment!(id), do: Repo.get!(Comment, id)

  def add_comment(%FeatureRequest{} = item, attrs, %User{} = user) do
    if can_comment_item?(item, user) do
      %Comment{}
      |> Comment.changeset(attrs)
      |> Ecto.Changeset.put_change(:forage_feature_request_id, item.id)
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def add_comment(_item, _attrs, _user), do: {:error, :unauthorized}

  def update_comment(%Comment{} = comment, attrs, %User{} = user) do
    if can_edit_comment?(comment, user) do
      comment
      |> Comment.changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def update_comment(_comment, _attrs, _user), do: {:error, :unauthorized}

  defp force_item_type(attrs, type) when is_map(attrs) do
    attrs
    |> Map.delete(:type)
    |> Map.delete("type")
    |> Map.put("type", Atom.to_string(type))
  end

  defdelegate list_grafana_alerts, to: Grafana, as: :list_alerts

  defp manual_item_entries(user) do
    list_manual_items()
    |> Enum.filter(&can_view_item?(&1, user))
    |> Enum.map(&manual_item_entry/1)
  end

  defp manual_item_entry(request) do
    %Item{
      id: "manual:#{request.id}",
      type: request.type,
      origin: :manual,
      source_record_id: request.id,
      source_record: request,
      title: request.title,
      body: request.description,
      status: request.status,
      visibility: request.visibility,
      source_label: "Hive",
      external_label: requester_label(request) || item_type_label(request.type),
      requester_label: requester_label(request),
      occurred_at: request.inserted_at,
      updated_at: request.updated_at || request.inserted_at,
      comments: loaded_comments(request),
      comments_status: :loaded,
      domains: []
    }
  end

  defp github_issue_item_entries(user) do
    user
    |> list_github_issues_for_user(state: nil)
    |> Enum.map(fn {repository, issue, domains} ->
      github_issue_item_entry(repository, issue, domains)
    end)
  end

  defp github_issue_item_entry(repository, issue, domains, opts \\ []) do
    {comments_status, comments, comments_error} =
      if Keyword.get(opts, :fetch_github_comments?, false) do
        github_issue_comments(repository, issue, opts)
      else
        {:not_loaded, [], nil}
      end

    %Item{
      id: "github_issue:#{issue.id}",
      type: :github_issue,
      origin: :github,
      source_record_id: issue.id,
      source_record: issue,
      title: issue.title,
      body: issue.body,
      status: issue.state,
      visibility: repository.visibility,
      source_label: GitHubRepository.full_name(repository),
      external_label: "##{issue.number}",
      external_url: GitHubIssue.html_url(%{issue | github_repository: repository}),
      repository_id: repository.id,
      occurred_at: issue.inserted_at,
      updated_at: issue.updated_at,
      comments: comments,
      comments_status: comments_status,
      comments_error: comments_error,
      domains: domains
    }
  end

  defp github_issue_comments(repository, issue, opts) do
    github_opts = Keyword.take(opts, [:config, :installation_token, :request])

    case Issues.list_comments(repository, issue.number, github_opts) do
      {:ok, comments} -> {:loaded, comments, nil}
      {:error, reason} -> {:error, [], reason}
    end
  end

  defp grafana_alert_item_entries(user) do
    source = get_source!(:grafana_alerts)

    if can_access?(source, user) do
      list_grafana_alerts()
      |> Enum.map(&grafana_alert_item_entry/1)
    else
      []
    end
  end

  defp grafana_alert_item_entry(alert) do
    project = alert.project

    %Item{
      id: "grafana_alert:#{alert.id}",
      type: :grafana_alert,
      origin: :grafana,
      source_record_id: alert.id,
      source_record: alert,
      title: alert.title,
      body: alert.summary || labels_summary(alert.labels),
      status: alert.status,
      visibility: :organization,
      source_label: "Grafana",
      external_label: project && project.name,
      external_url: alert.generator_url,
      occurred_at: alert.starts_at || alert.inserted_at,
      updated_at: alert.last_received_at || alert.updated_at,
      comments: [],
      comments_status: :not_available,
      domains: if(alert.domain, do: [alert.domain], else: [])
    }
  end

  defp get_manual_item(id) do
    comments_query =
      from(comment in Comment, order_by: [asc: comment.inserted_at], preload: [user: :identities])

    FeatureRequest
    |> preload([:user, comments: ^comments_query])
    |> Repo.get(id)
  end

  defp loaded_comments(%{comments: %Ecto.Association.NotLoaded{}}), do: []
  defp loaded_comments(%{comments: comments}) when is_list(comments), do: comments
  defp loaded_comments(_item), do: []

  defp grafana_filter_domains(user) do
    source = get_source!(:grafana_alerts)

    if can_access?(source, user) do
      list_grafana_alerts()
      |> Enum.map(& &1.domain)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp normalize_item_opts(opts) do
    %{
      type: normalize_choice(Keyword.get(opts, :type), item_types()),
      status: normalize_choice(Keyword.get(opts, :status), item_statuses()),
      domain_id: present_string(Keyword.get(opts, :domain_id)),
      repository_id: present_string(Keyword.get(opts, :repository_id)),
      query: present_string(Keyword.get(opts, :query)),
      page: parse_page(Keyword.get(opts, :page)),
      page_size: normalize_page_size(Keyword.get(opts, :page_size, @default_item_page_size))
    }
  end

  defp normalize_choice(nil, _choices), do: nil

  defp normalize_choice(value, choices) when is_atom(value) do
    if value in choices, do: value, else: nil
  end

  defp normalize_choice(value, choices) when is_binary(value) do
    Enum.find(choices, &(Atom.to_string(&1) == value))
  end

  defp normalize_choice(_value, _choices), do: nil

  defp present_string(nil), do: nil

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil

  defp parse_page(page) when is_integer(page) and page >= 1, do: page

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number >= 1 -> number
      _other -> 1
    end
  end

  defp parse_page(_page), do: 1

  defp normalize_page_size(:all), do: :all
  defp normalize_page_size(page_size) when is_integer(page_size) and page_size > 0, do: page_size
  defp normalize_page_size(_page_size), do: @default_item_page_size

  defp filter_items(items, opts) do
    items
    |> filter_item_type(opts.type)
    |> filter_item_status(opts.status)
    |> filter_item_domain(opts.domain_id)
    |> filter_item_repository(opts.repository_id)
    |> filter_item_search(opts.query)
  end

  defp filter_item_type(items, nil), do: items
  defp filter_item_type(items, type), do: Enum.filter(items, &(&1.type == type))

  defp filter_item_status(items, nil), do: items
  defp filter_item_status(items, status), do: Enum.filter(items, &(&1.status == status))

  defp filter_item_domain(items, nil), do: items

  defp filter_item_domain(items, domain_id) do
    Enum.filter(items, fn item -> Enum.any?(item.domains, &(&1.id == domain_id)) end)
  end

  defp filter_item_repository(items, nil), do: items

  defp filter_item_repository(items, repository_id) do
    Enum.filter(items, &(&1.repository_id == repository_id))
  end

  defp filter_item_search(items, nil), do: items

  defp filter_item_search(items, query) do
    query = String.downcase(query)

    Enum.filter(items, fn item ->
      item
      |> item_search_text()
      |> String.downcase()
      |> String.contains?(query)
    end)
  end

  defp item_search_text(item) do
    [
      item.title,
      item.body,
      item_type_label(item.type),
      item_status_label(item.status),
      item.source_label,
      item.external_label,
      item.requester_label,
      Enum.map(item.domains, & &1.name)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp paginate_items(items, _page, :all) do
    {items, pagination_meta(length(items), 1, :all)}
  end

  defp paginate_items(items, page, page_size) do
    total_count = length(items)
    total_pages = max(1, div(total_count + page_size - 1, page_size))
    current_page = min(page, total_pages)
    offset = (current_page - 1) * page_size

    {
      Enum.slice(items, offset, page_size),
      pagination_meta(total_count, current_page, page_size)
    }
  end

  defp pagination_meta(total_count, current_page, :all) do
    %{
      total_count: total_count,
      current_page: current_page,
      total_pages: 1,
      page_size: :all
    }
  end

  defp pagination_meta(total_count, current_page, page_size) do
    %{
      total_count: total_count,
      current_page: current_page,
      total_pages: max(1, div(total_count + page_size - 1, page_size)),
      page_size: page_size
    }
  end

  defp requester_label(%{user: %{email: email}}) when is_binary(email), do: email
  defp requester_label(_request), do: nil

  defp labels_summary(labels) when is_map(labels) do
    Enum.map_join(labels, ", ", fn {key, value} -> "#{key}: #{value}" end)
  end

  defp labels_summary(_labels), do: nil

  @doc """
  Returns `{repository, issue, domains}` triples for every cached GitHub
  issue the user is allowed to see. The `domains` element holds the
  domains the classifier assigned to the issue, filtered to the ones the
  user can access. Visibility is enforced through
  `accessible_domains_with_repositories/1`, so private repos stay hidden
  from anyone outside the organization.

  Options:
  - `:state` (default `:open`) — filter by issue state
  - `:domain_id` — restrict to issues classified into one domain
  - `:repository_id` — restrict to one repository
  """
  def list_github_issues_for_user(user, opts \\ []) do
    state = Keyword.get(opts, :state, :open)
    domain_id = Keyword.get(opts, :domain_id)
    repository_id = Keyword.get(opts, :repository_id)

    pairs = accessible_domains_with_repositories(user)
    accessible_domain_ids = pairs |> Enum.map(fn {domain, _repo} -> domain.id end) |> Enum.uniq()

    accessible_repository_ids =
      pairs |> Enum.map(fn {_domain, repo} -> repo.id end) |> Enum.uniq()

    repositories_by_id =
      pairs
      |> Enum.map(fn {_domain, repo} -> {repo.id, repo} end)
      |> Map.new()

    repository_ids = scope_repository_ids(accessible_repository_ids, repository_id)
    domain_scope = scope_domain_id(accessible_domain_ids, domain_id)

    GitHubIssue
    |> where([issue], issue.github_repository_id in ^repository_ids)
    |> maybe_filter_by_state(state)
    |> maybe_filter_by_domain(domain_scope)
    |> order_by([issue], desc: issue.updated_at)
    |> preload(:domains)
    |> Repo.all()
    |> Enum.flat_map(fn issue ->
      case Map.fetch(repositories_by_id, issue.github_repository_id) do
        {:ok, repository} ->
          visible_domains =
            issue.domains
            |> Enum.filter(&(&1.id in accessible_domain_ids))
            |> Enum.sort_by(& &1.name)

          [{repository, issue, visible_domains}]

        :error ->
          []
      end
    end)
  end

  defp scope_repository_ids(accessible_repository_ids, nil), do: accessible_repository_ids

  defp scope_repository_ids(accessible_repository_ids, repository_id) do
    if repository_id in accessible_repository_ids, do: [repository_id], else: []
  end

  defp scope_domain_id(_accessible_domain_ids, nil), do: nil

  defp scope_domain_id(accessible_domain_ids, domain_id) do
    if domain_id in accessible_domain_ids, do: domain_id, else: :none
  end

  defp maybe_filter_by_domain(query, nil), do: query
  defp maybe_filter_by_domain(query, :none), do: where(query, [_issue], false)

  defp maybe_filter_by_domain(query, domain_id) when is_binary(domain_id) do
    from issue in query,
      join: link in Hive.Forage.GitHubIssueDomain,
      on: link.forage_github_issue_id == issue.id,
      where: link.domain_id == ^domain_id,
      distinct: issue.id
  end

  defp maybe_filter_by_state(query, nil), do: query
  defp maybe_filter_by_state(query, state), do: where(query, [issue], issue.state == ^state)

  @doc """
  Upserts one GitHub issue or pull request into the forage cache without
  deleting anything else from the repository cache.
  """
  def upsert_repository_github_issue(%GitHubRepository{id: repository_id}, entry) do
    case upsert_entry(repository_id, entry) do
      {:ok, %GitHubIssue{} = issue, true} ->
        classify_issue(issue.id)
        Hive.Domains.schedule_evolution()
        {:ok, issue}

      {:ok, %GitHubIssue{} = issue, false} ->
        {:ok, issue}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Replaces the cached open issues for a single repository with `entries`.
  Each entry is a map with `:number`, `:title`, and `:body`. Issues that
  exist in the cache but are absent from `entries` are removed so the
  cache reflects only currently-open issues. Issues that are new or whose
  title or body changed are re-classified into domains so the dashboard
  groups them by the substance of the issue, not by the domains attached
  to the repository.
  """
  def reconcile_repository_github_issues(%GitHubRepository{id: repository_id}, entries) do
    incoming_numbers = entries |> Enum.map(& &1.number) |> Enum.uniq()

    dirty_issue_ids =
      Repo.transaction(fn ->
        dirty_ids =
          entries
          |> Enum.map(&dirty_issue_id(repository_id, &1))
          |> Enum.reject(&is_nil/1)

        delete_missing(repository_id, incoming_numbers)
        dirty_ids
      end)
      |> case do
        {:ok, ids} -> ids
        {:error, _} -> []
      end

    unclassified_ids = list_unclassified_issue_ids(repository_id)

    (dirty_issue_ids ++ unclassified_ids)
    |> Enum.uniq()
    |> Enum.each(&classify_issue/1)

    Hive.Domains.schedule_evolution()

    :ok
  end

  defp dirty_issue_id(repository_id, entry) do
    case upsert_entry(repository_id, entry) do
      {:ok, %GitHubIssue{id: id}, true} -> id
      {:ok, %GitHubIssue{}, false} -> nil
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp list_unclassified_issue_ids(repository_id) do
    GitHubIssue
    |> where(
      [issue],
      issue.github_repository_id == ^repository_id and is_nil(issue.classified_at) and
        is_nil(issue.classification_failed_at)
    )
    |> select([issue], issue.id)
    |> Repo.all()
  end

  defp upsert_entry(repository_id, entry) do
    attrs = %{
      github_repository_id: repository_id,
      number: entry.number,
      title: entry.title,
      body: entry.body,
      state: Map.get(entry, :state, :open)
    }

    existing = Repo.get_by(GitHubIssue, github_repository_id: repository_id, number: entry.number)
    content_changed? = content_changed?(existing, entry)

    attrs =
      if content_changed?,
        do:
          Map.merge(attrs, %{
            classified_at: nil,
            classification_failure: nil,
            classification_failed_at: nil
          }),
        else: attrs

    changeset =
      (existing || %GitHubIssue{})
      |> GitHubIssue.changeset(attrs)

    case Repo.insert_or_update(changeset) do
      {:ok, issue} -> {:ok, issue, content_changed?}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp content_changed?(nil, _entry), do: true

  defp content_changed?(%GitHubIssue{title: title, body: body}, entry) do
    title != entry.title or body != Map.get(entry, :body)
  end

  defp classify_issue(issue_id) do
    case GitHubIssueClassificationWorker.enqueue(issue_id) do
      :skipped -> GitHubIssueClassification.classify(issue_id)
      _result -> :ok
    end
  end

  defp delete_missing(repository_id, []) do
    GitHubIssue
    |> where([issue], issue.github_repository_id == ^repository_id)
    |> where([issue], issue.state == :open)
    |> Repo.delete_all()
  end

  defp delete_missing(repository_id, numbers) do
    GitHubIssue
    |> where([issue], issue.github_repository_id == ^repository_id)
    |> where([issue], issue.state == :open)
    |> where([issue], issue.number not in ^numbers)
    |> Repo.delete_all()
  end

  def list_repositories_with_domains do
    Domain
    |> preload(projects: :github_repositories)
    |> Repo.all()
    |> Enum.flat_map(fn domain ->
      repositories =
        domain.projects
        |> Enum.flat_map(& &1.github_repositories)
        |> Enum.uniq_by(& &1.id)

      Enum.map(repositories, &{domain, &1})
    end)
  end

  def list_github_issue_repositories do
    GitHubRepository
    |> where([repository], not is_nil(repository.project_id))
    |> order_by([repository], asc: repository.owner, asc: repository.name)
    |> Repo.all()
  end
end
