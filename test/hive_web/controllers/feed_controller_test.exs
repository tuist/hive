defmodule HiveWeb.FeedControllerTest do
  use HiveWeb.ConnCase, async: true

  import Ecto.Query

  alias Hive.Accounts
  alias Hive.Drops
  alias Hive.Forage
  alias Hive.Forage.Grafana
  alias Hive.Forage.GrafanaAlert
  alias Hive.Domains
  alias Hive.Projects
  alias Hive.Projects.Webhooks
  alias Hive.Repo
  alias Hive.Specs

  defp user(email) do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  defp member_user(email) do
    {:ok, member} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    {:ok, member} = Accounts.update_user_role(member, :member)
    member
  end

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = put_project_id(attrs, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  defp put_project_id(attrs, project_id) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put_new(attrs, "project_id", project_id)
    else
      Map.put_new(attrs, :project_id, project_id)
    end
  end

  describe "GET /forage/atom.xml" do
    test "renders an Atom feed listing visible forage items", %{conn: conn} do
      author = user("alice@example.com")

      {:ok, _request} =
        Forage.create_forage_item(
          %{
            "type" => "feedback",
            "title" => "Dark mode",
            "description" => "Add a dark theme."
          },
          author
        )

      conn = get(conn, ~p"/forage/atom.xml")

      assert response_content_type(conn, :xml) =~ "application/atom+xml"
      body = response(conn, 200)

      assert body =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert body =~ ~s(<feed xmlns="http://www.w3.org/2005/Atom">)
      assert body =~ "<title>Hive · Forage</title>"
      assert body =~ "/forage/atom.xml"
      assert body =~ "<entry>"
      assert body =~ "<title>Feedback: Dark mode</title>"
      assert body =~ "<summary>Add a dark theme.</summary>"
      assert body =~ "<name>alice@example.com</name>"
    end
  end

  describe "GET /forage/feature-requests/atom.xml" do
    test "renders an Atom feed listing public feature requests", %{conn: conn} do
      author = user("alice@example.com")

      {:ok, request} =
        Forage.create_feature_request(
          %{"title" => "Dark mode", "description" => "Add a dark theme."},
          author
        )

      conn = get(conn, ~p"/forage/feature-requests/atom.xml")

      assert response_content_type(conn, :xml) =~ "application/atom+xml"
      body = response(conn, 200)

      assert body =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert body =~ ~s(<feed xmlns="http://www.w3.org/2005/Atom">)
      assert body =~ "<title>Hive · Feature requests</title>"
      assert body =~ ~s(rel="self")
      assert body =~ "/forage/feature-requests/atom.xml"
      assert body =~ "<entry>"
      assert body =~ "<title>Dark mode</title>"
      assert body =~ "<summary>Add a dark theme.</summary>"
      assert body =~ "<name>alice@example.com</name>"
      assert body =~ "##{request.id}"
    end

    test "escapes XML-special characters in entries", %{conn: conn} do
      author = user("alice@example.com")

      {:ok, _} =
        Forage.create_feature_request(
          %{
            "title" => "Bug & crash <script>",
            "description" => "Breaks if title has <html> & quotes."
          },
          author
        )

      body = conn |> get(~p"/forage/feature-requests/atom.xml") |> response(200)

      refute body =~ "<script>"
      assert body =~ "Bug &amp; crash &lt;script&gt;"
      assert body =~ "Breaks if title has &lt;html&gt; &amp; quotes."
    end

    test "renders an empty feed when there are no entries", %{conn: conn} do
      body = conn |> get(~p"/forage/feature-requests/atom.xml") |> response(200)

      assert body =~ "<title>Hive · Feature requests</title>"
      refute body =~ "<entry>"
    end
  end

  describe "GET /specs/atom.xml" do
    test "anonymous requests only see public specs", %{conn: conn} do
      member = member_user("owner@example.com")

      {:ok, public_spec} =
        Specs.create_spec(
          %{
            "title" => "Public spec",
            "body" => "This is public content."
          },
          member
        )

      {:ok, _private_spec} =
        Specs.create_spec(
          %{
            "title" => "Private spec",
            "body" => "Members only content.",
            "visibility_override" => "private"
          },
          member
        )

      body = conn |> get(~p"/specs/atom.xml") |> response(200)

      assert body =~ "<title>Hive · Specs</title>"
      assert body =~ "##{public_spec.number} Public spec"
      refute body =~ "Private spec"
    end

    test "members see both public and private specs", %{conn: conn} do
      member = member_user("owner@example.com")
      {conn, _user} = sign_in(conn, "owner@example.com")

      {:ok, _public_spec} =
        Specs.create_spec(
          %{
            "title" => "Public spec",
            "body" => "Public content."
          },
          member
        )

      {:ok, _private_spec} =
        Specs.create_spec(
          %{
            "title" => "Private spec",
            "body" => "Members only content.",
            "visibility_override" => "private"
          },
          member
        )

      body = conn |> get(~p"/specs/atom.xml") |> response(200)

      assert body =~ "Public spec"
      assert body =~ "Private spec"
    end
  end

  describe "GET /forage/grafana-alerts/atom.xml" do
    test "returns 404 for anonymous users (organization-only source)", %{conn: conn} do
      conn = get(conn, ~p"/forage/grafana-alerts/atom.xml")

      assert response(conn, 404) =~ "<error/>"
    end

    test "returns an empty feed for organization members when there are no alerts", %{conn: conn} do
      _member = member_user("owner@example.com")
      {conn, _user} = sign_in(conn, "owner@example.com")

      body = conn |> get(~p"/forage/grafana-alerts/atom.xml") |> response(200)

      assert body =~ "<title>Hive · Grafana alerts</title>"
      refute body =~ "<entry>"
    end
  end

  describe "GET /forage/github-issues/atom.xml" do
    test "renders an empty feed when no accessible repositories exist", %{conn: conn} do
      body = conn |> get(~p"/forage/github-issues/atom.xml") |> response(200)

      assert body =~ "<title>Hive · GitHub issues</title>"
      refute body =~ "<entry>"
    end
  end

  describe "GET /forage/feature-requests/rss.xml" do
    test "renders an RSS 2.0 feed listing public feature requests", %{conn: conn} do
      author = user("alice@example.com")

      {:ok, _request} =
        Forage.create_feature_request(
          %{"title" => "Dark mode", "description" => "Add a dark theme."},
          author
        )

      conn = get(conn, ~p"/forage/feature-requests/rss.xml")

      assert response_content_type(conn, :xml) =~ "application/rss+xml"
      body = response(conn, 200)

      assert body =~ ~s(<rss version="2.0")
      assert body =~ "<channel>"
      assert body =~ "<title>Hive · Feature requests</title>"
      assert body =~ "/forage/feature-requests/rss.xml"
      assert body =~ "<item>"
      assert body =~ "<title>Dark mode</title>"
      assert body =~ "<pubDate>"
      assert body =~ "<author>alice@example.com (alice@example.com)</author>"
    end
  end

  describe "GET /specs/rss.xml" do
    test "anonymous requests only see public specs", %{conn: conn} do
      member = member_user("owner@example.com")

      {:ok, _public_spec} =
        Specs.create_spec(
          %{
            "title" => "Public spec",
            "body" => "Public content."
          },
          member
        )

      {:ok, _private_spec} =
        Specs.create_spec(
          %{
            "title" => "Private spec",
            "body" => "Members only content.",
            "visibility_override" => "private"
          },
          member
        )

      body = conn |> get(~p"/specs/rss.xml") |> response(200)

      assert body =~ "<title>Hive · Specs</title>"
      assert body =~ "Public spec"
      refute body =~ "Private spec"
    end
  end

  describe "GET /forage/grafana-alerts/rss.xml" do
    test "returns 404 for anonymous users", %{conn: conn} do
      conn = get(conn, ~p"/forage/grafana-alerts/rss.xml")
      assert response_content_type(conn, :xml) =~ "application/rss+xml"
      assert response(conn, 404) =~ "<error/>"
    end
  end

  describe "GET /drops/atom.xml" do
    test "uses the source permalink for drop entries", %{conn: conn} do
      domain = create_domain!(%{name: "drops-#{System.unique_integer([:positive])}"})

      {:ok, drop} =
        Drops.upsert_drop(%{
          source_type: :github_release,
          external_id: "tuist/hive@v1.0.0:pull-42",
          title: "Build cache warmups",
          body: "Warmups now reuse existing cache metadata before planning work.",
          url: "https://github.com/tuist/hive/pull/42",
          version: "v1.0.0",
          published_at: ~U[2026-06-18 09:30:00Z]
        })

      Drops.replace_drop_domains(drop, [domain.id])

      body = conn |> get(~p"/drops/atom.xml") |> response(200)

      assert body =~ ~s(<title>Build cache warmups</title>)

      assert body =~
               ~s(<link rel="alternate" type="text/html" href="https://github.com/tuist/hive/pull/42"/>)
    end
  end

  describe "GET /drops/rss.xml" do
    test "uses the changelog permalink for imported drop entries", %{conn: conn} do
      domain = create_domain!(%{name: "drops-#{System.unique_integer([:positive])}"})

      {:ok, drop} =
        Drops.upsert_drop(%{
          source_type: :rss,
          external_id: "https://example.com/changelog#2026-06-18",
          title: "Changelog entry",
          body: "A changelog update that belongs in the drops feed.",
          url: "https://example.com/changelog#2026-06-18",
          published_at: ~U[2026-06-18 09:30:00Z]
        })

      Drops.replace_drop_domains(drop, [domain.id])

      body = conn |> get(~p"/drops/rss.xml") |> response(200)

      assert body =~ "<title>Changelog entry</title>"
      assert body =~ "<link>https://example.com/changelog#2026-06-18</link>"
      assert body =~ ~s(<guid isPermaLink="true">https://example.com/changelog#2026-06-18</guid>)
    end
  end

  describe "feed discovery and dropdown" do
    test "forage page advertises both Atom and RSS feeds", %{conn: conn} do
      body = conn |> get(~p"/forage") |> html_response(200)

      assert body =~
               ~s(rel="alternate" type="application/atom+xml" title="Hive · Forage" href="/forage/atom.xml")

      assert body =~
               ~s(rel="alternate" type="application/rss+xml" title="Hive · Forage" href="/forage/rss.xml")
    end

    test "specs index advertises both Atom and RSS feeds", %{conn: conn} do
      body = conn |> get(~p"/specs") |> html_response(200)

      assert body =~
               ~s(rel="alternate" type="application/atom+xml" title="Hive · Specs" href="/specs/atom.xml")

      assert body =~
               ~s(rel="alternate" type="application/rss+xml" title="Hive · Specs" href="/specs/rss.xml")
    end

    test "forage page renders the feeds dropdown with both links", %{conn: conn} do
      body = conn |> get(~p"/forage") |> html_response(200)

      assert body =~ ~s(id="forage-feeds-dropdown")
      assert body =~ "/forage/atom.xml"
      assert body =~ "/forage/rss.xml"
    end

    test "specs index renders the feeds dropdown with both links", %{conn: conn} do
      body = conn |> get(~p"/specs") |> html_response(200)

      assert body =~ ~s(id="specs-index-feeds-dropdown")
      assert body =~ "/specs/atom.xml"
      assert body =~ "/specs/rss.xml"
    end
  end

  describe "GET /domains/:id/atom.xml" do
    test "returns 404 for a missing domain", %{conn: conn} do
      conn = get(conn, ~p"/domains/00000000-0000-0000-0000-000000000000/atom.xml")

      assert response(conn, 404) =~ "<error/>"
    end

    test "returns 404 to anonymous viewers for a private domain", %{conn: conn} do
      domain = create_domain!(%{"name" => "Private", "visibility" => "private"})

      conn = get(conn, ~p"/domains/#{domain.id}/atom.xml")

      assert response(conn, 404) =~ "<error/>"
    end

    test "lists GitHub issues for a public domain with a public repository", %{conn: conn} do
      suffix = System.unique_integer([:positive])

      domain =
        create_domain!(%{
          name: "atlas-#{suffix}",
          visibility: "public",
          github_repository_owner: "tuist",
          github_repository_name: "hive-#{suffix}",
          github_repository_visibility: "public"
        })

      repository = github_repository_for_domain!(domain)

      Forage.reconcile_repository_github_issues(repository, [
        %{number: 42, title: "Add dark mode", body: "Please."}
      ])

      body = conn |> get(~p"/domains/#{domain.id}/atom.xml") |> response(200)

      assert body =~ "<feed xmlns="
      assert body =~ "<title>Hive · atlas-#{suffix}</title>"
      assert body =~ "Add dark mode"
      assert body =~ "tuist/hive-#{suffix}##{42}"
    end

    test "includes grafana alerts for organization members", %{conn: conn} do
      member_user("member@example.com")
      {conn, _user} = sign_in(conn, "member@example.com")
      suffix = System.unique_integer([:positive])

      domain = create_domain!(%{name: "ops-#{suffix}", visibility: "public"})
      project = List.first(domain.projects)

      {:ok, {webhook, _token}} =
        Webhooks.create(project, %{"source" => "grafana", "name" => "grafana-webhook"})

      {:ok, alerts} =
        Grafana.ingest(project, webhook, %{
          "alerts" => [
            %{
              "status" => "firing",
              "fingerprint" => "abc#{suffix}",
              "labels" => %{"alertname" => "HighLatency"},
              "annotations" => %{"summary" => "Latency spiking"}
            }
          ]
        })

      assign_alerts_to_domain(alerts, domain)

      body = conn |> get(~p"/domains/#{domain.id}/atom.xml") |> response(200)

      assert body =~ "Latency spiking"
      assert body =~ "[Firing]"
    end

    test "hides grafana alerts from anonymous viewers", %{conn: conn} do
      suffix = System.unique_integer([:positive])

      domain = create_domain!(%{name: "ops-#{suffix}", visibility: "public"})
      project = List.first(domain.projects)

      {:ok, {webhook, _token}} =
        Webhooks.create(project, %{"source" => "grafana", "name" => "grafana-webhook"})

      {:ok, alerts} =
        Grafana.ingest(project, webhook, %{
          "alerts" => [
            %{
              "status" => "firing",
              "fingerprint" => "abc#{suffix}",
              "labels" => %{"alertname" => "HighLatency"},
              "annotations" => %{"summary" => "Latency spiking"}
            }
          ]
        })

      assign_alerts_to_domain(alerts, domain)

      body = conn |> get(~p"/domains/#{domain.id}/atom.xml") |> response(200)

      refute body =~ "Latency spiking"
    end
  end

  defp assign_alerts_to_domain(alerts, domain) do
    alert_ids = Enum.map(alerts, & &1.id)

    Repo.update_all(
      from(alert in GrafanaAlert, where: alert.id in ^alert_ids),
      set: [domain_id: domain.id]
    )
  end

  describe "GET /domains/:id/rss.xml" do
    test "renders the same content as Atom in RSS 2.0 wrapping", %{conn: conn} do
      suffix = System.unique_integer([:positive])

      domain =
        create_domain!(%{
          name: "atlas-#{suffix}",
          visibility: "public",
          github_repository_owner: "tuist",
          github_repository_name: "hive-#{suffix}",
          github_repository_visibility: "public"
        })

      repository = github_repository_for_domain!(domain)

      Forage.reconcile_repository_github_issues(repository, [
        %{number: 7, title: "Dark mode", body: "Please."}
      ])

      conn = get(conn, ~p"/domains/#{domain.id}/rss.xml")
      assert response_content_type(conn, :xml) =~ "application/rss+xml"
      body = response(conn, 200)

      assert body =~ ~s(<rss version="2.0")
      assert body =~ "Dark mode"
    end
  end

  describe "domain feed discovery" do
    test "domain detail advertises feeds and renders the dropdown", %{conn: conn} do
      domain = create_domain!(%{"name" => "Hive", "visibility" => "public"})

      body = conn |> get(~p"/domains/#{domain.id}") |> html_response(200)

      assert body =~
               ~s(rel="alternate" type="application/atom+xml" title="Hive · Hive" href="/domains/#{domain.id}/atom.xml")

      assert body =~
               ~s(rel="alternate" type="application/rss+xml" title="Hive · Hive" href="/domains/#{domain.id}/rss.xml")

      assert body =~ ~s(id="domain-#{domain.id}-feeds-dropdown")
    end
  end
end
