defmodule HiveWeb.FeedControllerTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Forage
  alias Hive.Forage.Grafana
  alias Hive.Meadows
  alias Hive.Meadows.Webhooks
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
            "body" => "This is public content.",
            "visibility" => "public"
          },
          member
        )

      {:ok, _private_spec} =
        Specs.create_spec(
          %{
            "title" => "Private spec",
            "body" => "Members only content.",
            "visibility" => "private"
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
            "body" => "Public content.",
            "visibility" => "public"
          },
          member
        )

      {:ok, _private_spec} =
        Specs.create_spec(
          %{
            "title" => "Private spec",
            "body" => "Members only content.",
            "visibility" => "private"
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
            "body" => "Public content.",
            "visibility" => "public"
          },
          member
        )

      {:ok, _private_spec} =
        Specs.create_spec(
          %{
            "title" => "Private spec",
            "body" => "Members only content.",
            "visibility" => "private"
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

  describe "feed discovery and dropdown" do
    test "feature-requests page advertises both Atom and RSS feeds", %{conn: conn} do
      body = conn |> get(~p"/forage/feature-requests") |> html_response(200)

      assert body =~
               ~s(rel="alternate" type="application/atom+xml" title="Hive · Feature requests" href="/forage/feature-requests/atom.xml")

      assert body =~
               ~s(rel="alternate" type="application/rss+xml" title="Hive · Feature requests" href="/forage/feature-requests/rss.xml")
    end

    test "specs index advertises both Atom and RSS feeds", %{conn: conn} do
      body = conn |> get(~p"/specs") |> html_response(200)

      assert body =~
               ~s(rel="alternate" type="application/atom+xml" title="Hive · Specs" href="/specs/atom.xml")

      assert body =~
               ~s(rel="alternate" type="application/rss+xml" title="Hive · Specs" href="/specs/rss.xml")
    end

    test "feature-requests page renders the feeds dropdown with both links", %{conn: conn} do
      body = conn |> get(~p"/forage/feature-requests") |> html_response(200)

      assert body =~ ~s(id="forage-feature_requests-feeds-dropdown")
      assert body =~ "/forage/feature-requests/atom.xml"
      assert body =~ "/forage/feature-requests/rss.xml"
    end

    test "specs index renders the feeds dropdown with both links", %{conn: conn} do
      body = conn |> get(~p"/specs") |> html_response(200)

      assert body =~ ~s(id="specs-index-feeds-dropdown")
      assert body =~ "/specs/atom.xml"
      assert body =~ "/specs/rss.xml"
    end
  end

  describe "GET /meadows/:id/atom.xml" do
    test "returns 404 for a missing meadow", %{conn: conn} do
      conn = get(conn, ~p"/meadows/00000000-0000-0000-0000-000000000000/atom.xml")

      assert response(conn, 404) =~ "<error/>"
    end

    test "returns 404 to anonymous viewers for a private meadow", %{conn: conn} do
      {:ok, meadow} = Meadows.create_meadow(%{"name" => "Private", "visibility" => "private"})

      conn = get(conn, ~p"/meadows/#{meadow.id}/atom.xml")

      assert response(conn, 404) =~ "<error/>"
    end

    test "lists GitHub issues for a public meadow with a public repository", %{conn: conn} do
      suffix = System.unique_integer([:positive])

      {:ok, meadow} =
        Meadows.create_meadow(%{
          name: "atlas-#{suffix}",
          visibility: "public",
          github_repository_owner: "tuist",
          github_repository_name: "hive-#{suffix}",
          github_repository_visibility: "public"
        })

      repository = hd(meadow.github_repositories)

      Forage.reconcile_repository_github_issues(repository, [
        %{number: 42, title: "Add dark mode", body: "Please."}
      ])

      body = conn |> get(~p"/meadows/#{meadow.id}/atom.xml") |> response(200)

      assert body =~ "<feed xmlns="
      assert body =~ "<title>Hive · atlas-#{suffix}</title>"
      assert body =~ "Add dark mode"
      assert body =~ "tuist/hive-#{suffix}##{42}"
    end

    test "includes grafana alerts for organization members", %{conn: conn} do
      member_user("member@example.com")
      {conn, _user} = sign_in(conn, "member@example.com")
      suffix = System.unique_integer([:positive])

      {:ok, meadow} =
        Meadows.create_meadow(%{name: "ops-#{suffix}", visibility: "public"})

      {:ok, {webhook, _token}} =
        Webhooks.create(meadow, %{"source" => "grafana", "name" => "grafana-webhook"})

      {:ok, _alerts} =
        Grafana.ingest(meadow, webhook, %{
          "alerts" => [
            %{
              "status" => "firing",
              "fingerprint" => "abc#{suffix}",
              "labels" => %{"alertname" => "HighLatency"},
              "annotations" => %{"summary" => "Latency spiking"}
            }
          ]
        })

      body = conn |> get(~p"/meadows/#{meadow.id}/atom.xml") |> response(200)

      assert body =~ "Latency spiking"
      assert body =~ "[Firing]"
    end

    test "hides grafana alerts from anonymous viewers", %{conn: conn} do
      suffix = System.unique_integer([:positive])

      {:ok, meadow} =
        Meadows.create_meadow(%{name: "ops-#{suffix}", visibility: "public"})

      {:ok, {webhook, _token}} =
        Webhooks.create(meadow, %{"source" => "grafana", "name" => "grafana-webhook"})

      {:ok, _alerts} =
        Grafana.ingest(meadow, webhook, %{
          "alerts" => [
            %{
              "status" => "firing",
              "fingerprint" => "abc#{suffix}",
              "labels" => %{"alertname" => "HighLatency"},
              "annotations" => %{"summary" => "Latency spiking"}
            }
          ]
        })

      body = conn |> get(~p"/meadows/#{meadow.id}/atom.xml") |> response(200)

      refute body =~ "Latency spiking"
    end
  end

  describe "GET /meadows/:id/rss.xml" do
    test "renders the same content as Atom in RSS 2.0 wrapping", %{conn: conn} do
      suffix = System.unique_integer([:positive])

      {:ok, meadow} =
        Meadows.create_meadow(%{
          name: "atlas-#{suffix}",
          visibility: "public",
          github_repository_owner: "tuist",
          github_repository_name: "hive-#{suffix}",
          github_repository_visibility: "public"
        })

      repository = hd(meadow.github_repositories)

      Forage.reconcile_repository_github_issues(repository, [
        %{number: 7, title: "Dark mode", body: "Please."}
      ])

      conn = get(conn, ~p"/meadows/#{meadow.id}/rss.xml")
      assert response_content_type(conn, :xml) =~ "application/rss+xml"
      body = response(conn, 200)

      assert body =~ ~s(<rss version="2.0")
      assert body =~ "Dark mode"
    end
  end

  describe "meadow feed discovery" do
    test "meadow detail advertises feeds and renders the dropdown", %{conn: conn} do
      {:ok, meadow} = Meadows.create_meadow(%{"name" => "Hive", "visibility" => "public"})

      body = conn |> get(~p"/meadows/#{meadow.id}") |> html_response(200)

      assert body =~
               ~s(rel="alternate" type="application/atom+xml" title="Hive · Hive" href="/meadows/#{meadow.id}/atom.xml")

      assert body =~
               ~s(rel="alternate" type="application/rss+xml" title="Hive · Hive" href="/meadows/#{meadow.id}/rss.xml")

      assert body =~ ~s(id="meadow-#{meadow.id}-feeds-dropdown")
    end
  end
end
