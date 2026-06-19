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
  alias Hive.Meadows
  alias Hive.Specs
  alias HiveWeb.Atom, as: AtomFeed
  alias HiveWeb.Endpoint
  alias HiveWeb.Rss

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

  def meadow_atom(conn, %{"id" => id}), do: serve_meadow(conn, id, :atom)
  def meadow_rss(conn, %{"id" => id}), do: serve_meadow(conn, id, :rss)

  def meadow_drops_atom(conn, %{"id" => id}), do: serve_meadow_drops(conn, id, :atom)
  def meadow_drops_rss(conn, %{"id" => id}), do: serve_meadow_drops(conn, id, :rss)

  defp forage_feed(conn) do
    user = Auth.current_user(conn)
    {items, _meta} = Forage.list_forage_items_for_user(user, page_size: :all)

    %{
      id: feed_id(conn),
      title: "Hive · Forage",
      subtitle:
        "Feature requests, bug reports, feedback, GitHub issues, and Grafana alerts in one queue.",
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
      title: "Hive · Feature requests",
      subtitle: "Public meadow ideas submitted by authenticated users.",
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
      title: "Hive · GitHub issues",
      subtitle: "Open issues from GitHub repositories connected to meadows.",
      updated: latest_updated(triples, fn {_repo, issue, _meadows} -> issue.updated_at end),
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
      title: "Hive · Grafana alerts",
      subtitle: "Operational signals visible only to organization members.",
      updated: latest_updated(alerts, fn alert -> alert.last_received_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/forage/grafana-alerts"),
      entries: Enum.map(alerts, &grafana_alert_entry(conn, &1))
    }
  end

  defp serve_meadow(conn, id, format) do
    user = Auth.current_user(conn)

    case Meadows.fetch_visible_meadow(id, user) do
      {:ok, meadow} -> send_feed(conn, format, meadow_feed(conn, meadow, user))
      {:error, :not_found} -> not_found(conn, format)
    end
  end

  defp meadow_feed(conn, meadow, user) do
    issues = Forage.list_github_issues_for_user(user, meadow_id: meadow.id, state: nil)

    alerts =
      if Auth.member?(user),
        do: Grafana.list_alerts_for_meadow(meadow.id),
        else: []

    drops = Drops.list_drops_for_meadow(meadow)

    entries =
      (Enum.map(issues, &github_issue_entry/1) ++
         Enum.map(alerts, &grafana_alert_entry(conn, &1)) ++
         Enum.map(drops, &drop_entry/1))
      |> Enum.sort_by(& &1.updated, {:desc, DateTime})

    %{
      id: feed_id(conn),
      title: "Hive · #{meadow.name}",
      subtitle: meadow.description || "Updates belonging to the #{meadow.name} meadow.",
      updated: latest_entry_updated(entries),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/meadows/#{meadow.id}"),
      entries: entries
    }
  end

  defp drops_feed(conn, params) do
    user = Auth.current_user(conn)
    meadow_ids = parse_meadow_ids(params["meadow_ids"])

    {drops, _meta} =
      Drops.list_drops(user: user, meadow_ids: meadow_ids, page_size: :all)

    %{
      id: feed_id(conn),
      title: "Hive · Drops",
      subtitle: "Shipped updates from GitHub releases and changelog feeds across every meadow.",
      updated: latest_updated(drops, fn drop -> drop.published_at || drop.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/drops"),
      entries: Enum.map(drops, &drop_entry/1)
    }
  end

  defp serve_meadow_drops(conn, id, format) do
    user = Auth.current_user(conn)

    case Meadows.fetch_visible_meadow(id, user) do
      {:ok, meadow} -> send_feed(conn, format, meadow_drops_feed(conn, meadow))
      {:error, :not_found} -> not_found(conn, format)
    end
  end

  defp meadow_drops_feed(conn, meadow) do
    drops = Drops.list_drops_for_meadow(meadow)

    %{
      id: feed_id(conn),
      title: "Hive · #{meadow.name} drops",
      subtitle:
        meadow.description ||
          "Shipped updates from the #{meadow.name} meadow.",
      updated: latest_updated(drops, fn drop -> drop.published_at || drop.updated_at end),
      self_url: feed_url(conn),
      alternate_url: page_url(conn, "/drops?meadow_ids=#{meadow.id}"),
      entries: Enum.map(drops, &drop_entry/1)
    }
  end

  defp drop_entry(drop) do
    repo_prefix =
      case drop.github_repository do
        %{owner: owner, name: name} -> "#{owner}/#{name}: "
        _other -> ""
      end

    %{
      id: "urn:hive:drop:#{drop.id}",
      title: repo_prefix <> drop.title,
      updated: drop.published_at || drop.updated_at,
      url: drop.url,
      summary: drop.body
    }
  end

  defp parse_meadow_ids(nil), do: []

  defp parse_meadow_ids(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_meadow_ids(_value), do: []

  defp latest_entry_updated([]), do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp latest_entry_updated([first | _rest]), do: first.updated

  defp specs_feed(conn) do
    user = Auth.current_user(conn)
    specs = Specs.list_specs(user: user)

    %{
      id: feed_id(conn),
      title: "Hive · Specs",
      subtitle: "Editable proposals that shape forage into buildable work.",
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
      title: "#{Forage.item_type_label(item.type)}: #{item.title}",
      updated: item.updated_at,
      url: url,
      summary: item.body,
      author_name: item.requester_label,
      author_email: item.requester_label
    }
  end

  defp github_issue_entry({repository, issue, _meadows}) do
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
    status_label = alert.status |> Atom.to_string() |> String.capitalize()

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
