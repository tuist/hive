defmodule HiveWeb.FeedController do
  @moduledoc """
  Serves Atom 1.0 and RSS 2.0 feeds for forage sources and specs.

  Each list-style HTML page has sibling `*/atom.xml` and `*/rss.xml`
  endpoints so people can subscribe through any reader. The same context
  modules back both formats and the HTML page, and visibility is enforced
  the same way: only the items the current request can read appear in
  the response.
  """

  use HiveWeb, :controller

  alias Hive.Auth
  alias Hive.Drops
  alias Hive.Forage
  alias Hive.Forage.Grafana
  alias Hive.Domains
  alias Hive.Projects
  alias Hive.Specs
  alias HiveWeb.Atom, as: AtomFeed
  alias HiveWeb.Endpoint
  alias HiveWeb.Rss
  alias HiveWeb.Utilities.Query

  def forage_atom(conn, _params), do: send_feed(conn, :atom, forage_feed(conn))
  def forage_rss(conn, _params), do: send_feed(conn, :rss, forage_feed(conn))

  def feature_requests_atom(conn, _params),
    do: send_feed(conn, :atom, feature_requests_feed(conn))

  def feature_requests_rss(conn, _params), do: send_feed(conn, :rss, feature_requests_feed(conn))

  def github_issues_atom(conn, _params), do: send_feed(conn, :atom, github_issues_feed(conn))
  def github_issues_rss(conn, _params), do: send_feed(conn, :rss, github_issues_feed(conn))

  def grafana_alerts_atom(conn, _params), do: serve_grafana(conn, :atom)
  def grafana_alerts_rss(conn, _params), do: serve_grafana(conn, :rss)

  def specs_atom(conn, _params), do: send_feed(conn, :atom, specs_feed(conn))
  def specs_rss(conn, _params), do: send_feed(conn, :rss, specs_feed(conn))

  def drops_atom(conn, params), do: send_feed(conn, :atom, drops_feed(conn, params))
  def drops_rss(conn, params), do: send_feed(conn, :rss, drops_feed(conn, params))

  def domain_atom(conn, %{"id" => id}), do: serve_domain(conn, id, :atom)
  def domain_rss(conn, %{"id" => id}), do: serve_domain(conn, id, :rss)

  def domain_drops_atom(conn, %{"id" => id}), do: serve_domain_drops(conn, id, :atom)
  def domain_drops_rss(conn, %{"id" => id}), do: serve_domain_drops(conn, id, :rss)

  def project_drops_atom(conn, %{"id" => id}), do: serve_project_drops(conn, id, :atom)
  def project_drops_rss(conn, %{"id" => id}), do: serve_project_drops(conn, id, :rss)

  defp forage_feed(conn) do
    user = Auth.current_user(conn)
    {items, _meta} = Forage.list_forage_items_for_user(user, page_size: :all)

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_forage", "Hive · Forage"),
      subtitle:
        dgettext(
          "dashboard_forage",
          "Feature requests, bug reports, feedback, GitHub issues, and Grafana alerts in one queue."
        ),
      updated: latest_updated(items, fn item -> item.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/forage"),
      entries: Enum.map(items, &forage_item_entry(conn, &1))
    }
  end

  defp feature_requests_feed(conn) do
    feature_requests = Forage.list_feature_requests()

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_forage", "Hive · Feature requests"),
      subtitle:
        dgettext("dashboard_forage", "Public domain ideas submitted by authenticated users."),
      updated: latest_updated(feature_requests, fn fr -> fr.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/forage/feature-requests"),
      entries: Enum.map(feature_requests, &feature_request_entry(conn, &1))
    }
  end

  defp github_issues_feed(conn) do
    user = Auth.current_user(conn)
    triples = Forage.list_github_issues_for_user(user)

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_forage", "Hive · GitHub issues"),
      subtitle:
        dgettext("dashboard_forage", "Open issues from GitHub repositories connected to domains."),
      updated: latest_updated(triples, fn {_repo, issue, _domains} -> issue.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/forage/github-issues"),
      entries: Enum.map(triples, &github_issue_entry/1)
    }
  end

  defp serve_grafana(conn, format) do
    user = Auth.current_user(conn)
    source = Forage.get_source!(:grafana_alerts)

    if Forage.can_access?(source, user) do
      send_feed(conn, format, grafana_alerts_feed(conn))
    else
      not_found(conn, format)
    end
  end

  defp grafana_alerts_feed(conn) do
    alerts = Forage.list_grafana_alerts()

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_forage", "Hive · Grafana alerts"),
      subtitle:
        dgettext("dashboard_forage", "Operational signals visible only to organization members."),
      updated: latest_updated(alerts, fn alert -> alert.last_received_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/forage/grafana-alerts"),
      entries: Enum.map(alerts, &grafana_alert_entry(conn, &1))
    }
  end

  defp serve_domain(conn, id, format) do
    user = Auth.current_user(conn)

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} -> send_feed(conn, format, domain_feed(conn, domain, user))
      {:error, :not_found} -> not_found(conn, format)
    end
  end

  defp domain_feed(conn, domain, user) do
    issues = Forage.list_github_issues_for_user(user, domain_id: domain.id, state: nil)

    alerts =
      if Auth.member?(user),
        do: Grafana.list_alerts_for_domain(domain.id),
        else: []

    drops = Drops.list_drops_for_domain(domain)

    entries =
      (Enum.map(issues, &github_issue_entry/1) ++
         Enum.map(alerts, &grafana_alert_entry(conn, &1)) ++
         Enum.map(drops, &drop_entry(conn, &1)))
      |> Enum.sort_by(& &1.updated, {:desc, DateTime})

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_domains", "Hive · %{domain}", domain: domain.name),
      subtitle:
        domain.description ||
          dgettext("dashboard_domains", "Updates belonging to the %{domain} domain.",
            domain: domain.name
          ),
      updated: latest_entry_updated(entries),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/domains/#{domain.id}"),
      entries: entries
    }
  end

  defp drops_feed(conn, params) do
    user = Auth.current_user(conn)
    domain_ids = parse_domain_ids(params["domain_ids"])
    project_ids = parse_project_ids(params["project_ids"])

    {drops, _meta} =
      Drops.list_drops(
        user: user,
        domain_ids: domain_ids,
        project_ids: project_ids,
        page_size: :all
      )

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_drops", "Hive · Drops"),
      subtitle:
        dgettext(
          "dashboard_drops",
          "Shipped updates from GitHub releases and changelog feeds across every domain."
        ),
      updated: latest_updated(drops, fn drop -> drop.published_at || drop.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/drops" <> drops_filter_query(project_ids, domain_ids)),
      entries: Enum.map(drops, &drop_entry(conn, &1))
    }
  end

  defp serve_domain_drops(conn, id, format) do
    user = Auth.current_user(conn)

    case Domains.fetch_visible_domain(id, user) do
      {:ok, domain} -> send_feed(conn, format, domain_drops_feed(conn, domain))
      {:error, :not_found} -> not_found(conn, format)
    end
  end

  defp domain_drops_feed(conn, domain) do
    drops = Drops.list_drops_for_domain(domain)

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_drops", "Hive · %{domain} drops", domain: domain.name),
      subtitle:
        domain.description ||
          dgettext("dashboard_drops", "Shipped updates from the %{domain} domain.",
            domain: domain.name
          ),
      updated: latest_updated(drops, fn drop -> drop.published_at || drop.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/drops?domain_ids=#{domain.id}"),
      entries: Enum.map(drops, &drop_entry(conn, &1))
    }
  end

  defp serve_project_drops(conn, id, format) do
    user = Auth.current_user(conn)

    case Projects.fetch_visible_project(id, user) do
      {:ok, project} -> send_feed(conn, format, project_drops_feed(conn, project, user))
      {:error, :not_found} -> not_found(conn, format)
    end
  end

  defp project_drops_feed(conn, project, user) do
    drops = Drops.list_drops_for_project(project, user: user)

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_drops", "Hive · %{project} drops", project: project.name),
      subtitle:
        project.description ||
          dgettext("dashboard_drops", "Shipped updates from the %{project} project.",
            project: project.name
          ),
      updated: latest_updated(drops, fn drop -> drop.published_at || drop.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/projects/#{project.id}"),
      entries: Enum.map(drops, &drop_entry(conn, &1))
    }
  end

  defp drop_entry(conn, drop) do
    repo_prefix =
      case drop.github_repository do
        %{owner: owner, name: name} -> "#{owner}/#{name}: "
        _other -> ""
      end

    url = source_url(drop) || page_url(conn, Drops.public_path(drop))

    %{
      id: "urn:hive:drop:#{drop.number}",
      title: repo_prefix <> drop.title,
      updated: drop.published_at || drop.updated_at,
      url: url,
      summary: drop.body
    }
  end

  defp source_url(%{url: url}) when is_binary(url) and url != "", do: url
  defp source_url(_drop), do: nil

  defp parse_domain_ids(nil), do: []
  defp parse_domain_ids(value), do: Query.csv_list(value)
  defp parse_project_ids(nil), do: []
  defp parse_project_ids(value), do: Query.csv_list(value)

  defp drops_filter_query([], []), do: ""

  defp drops_filter_query(project_ids, domain_ids) do
    params =
      %{}
      |> maybe_put_csv("project_ids", project_ids)
      |> maybe_put_csv("domain_ids", domain_ids)

    "?" <> URI.encode_query(params)
  end

  defp maybe_put_csv(params, _key, []), do: params
  defp maybe_put_csv(params, key, values), do: Map.put(params, key, Enum.join(values, ","))

  defp latest_entry_updated([]), do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp latest_entry_updated([first | _rest]), do: first.updated

  defp specs_feed(conn) do
    user = Auth.current_user(conn)
    specs = Specs.list_specs(user: user)

    %{
      id: feed_id(conn),
      title: dgettext("dashboard_specs", "Hive · Specs"),
      subtitle:
        dgettext("dashboard_specs", "Editable proposals that shape forage into buildable work."),
      updated: latest_updated(specs, fn spec -> spec.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/specs"),
      entries: Enum.map(specs, &spec_entry(conn, &1))
    }
  end

  defp feature_request_entry(conn, request) do
    %{
      id: page_url(conn, "/forage/feature-requests") <> "##{request.id}",
      title: request.title,
      updated: request.updated_at,
      url: page_url(conn, "/forage/feature-requests") <> "##{request.id}",
      summary: request.description,
      author_name: author_name(request.user),
      author_email: author_email(request.user)
    }
  end

  defp forage_item_entry(conn, item) do
    url = item.external_url || page_url(conn, "/forage") <> "##{item.id}"

    %{
      id: "urn:hive:forage-item:#{item.id}",
      title:
        dgettext("dashboard_forage", "%{type}: %{title}",
          type: Forage.item_type_label(item.type),
          title: item.title
        ),
      updated: item.updated_at,
      url: url,
      summary: item.body,
      author_name: item.requester_label,
      author_email: item.requester_label
    }
  end

  defp github_issue_entry({repository, issue, _domains}) do
    url = "https://github.com/#{repository.owner}/#{repository.name}/issues/#{issue.number}"

    %{
      id: url,
      title: "#{repository.owner}/#{repository.name}##{issue.number}: #{issue.title}",
      updated: issue.updated_at,
      url: url,
      summary: issue.body
    }
  end

  defp grafana_alert_entry(conn, alert) do
    url = alert.generator_url || page_url(conn, "/forage/grafana-alerts")
    status_label = Forage.item_status_label(alert.status)

    %{
      id: "urn:hive:grafana-alert:#{alert.id}",
      title: "[#{status_label}] #{alert.title}",
      updated: alert.last_received_at,
      url: url,
      summary: alert.summary
    }
  end

  defp spec_entry(conn, spec) do
    url = page_url(conn, "/specs/#{spec.number}")

    %{
      id: url,
      title: "##{spec.number} #{spec.title}",
      updated: spec.updated_at,
      url: url,
      summary: spec.summary || spec.body,
      author_name: author_name(spec.created_by_user),
      author_email: author_email(spec.created_by_user)
    }
  end

  defp author_name(%{email: email}) when is_binary(email), do: email
  defp author_name(_), do: nil

  defp author_email(%{email: email}) when is_binary(email), do: email
  defp author_email(_), do: nil

  defp latest_updated([], _fun), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp latest_updated(entries, fun) do
    entries
    |> Enum.map(fun)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> DateTime.utc_now() |> DateTime.truncate(:second)
      stamps -> stamps |> Enum.map(&to_datetime/1) |> Enum.max(DateTime)
    end
  end

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp feed_url(conn), do: page_url(conn, conn.request_path)

  defp page_url(_conn, path) do
    Endpoint.url() <> path
  end

  defp feed_id(conn) do
    "urn:hive:feed:" <> conn.request_path
  end

  defp send_feed(conn, :atom, feed) do
    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(200, AtomFeed.render(feed))
  end

  defp send_feed(conn, :rss, feed) do
    conn
    |> put_resp_content_type("application/rss+xml")
    |> send_resp(200, Rss.render(feed))
  end

  defp not_found(conn, :atom) do
    conn
    |> put_resp_content_type("application/atom+xml")
    |> send_resp(404, ~s(<?xml version="1.0" encoding="UTF-8"?>\n<error/>\n))
  end

  defp not_found(conn, :rss) do
    conn
    |> put_resp_content_type("application/rss+xml")
    |> send_resp(404, ~s(<?xml version="1.0" encoding="UTF-8"?>\n<error/>\n))
  end
end
