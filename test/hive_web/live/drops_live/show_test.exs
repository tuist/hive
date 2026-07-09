defmodule HiveWeb.DropsLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Drops
  alias Hive.Domains
  alias Hive.Projects
  alias HiveWeb.OpenGraph

  defp unique_domain_name(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

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

  defp insert_drop!(domain, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          source_type: :github_release,
          external_id: "tuist/hive@v0.25.0#slack-#{System.unique_integer([:positive])}",
          title: "Slack workspace management moved to Ops",
          body:
            "Admins now manage connected Slack workspaces from the Ops surface at `/ops/slack`.",
          url: "https://github.com/tuist/hive/releases/tag/v0.25.0",
          version: "v0.25.0",
          published_at: ~U[2026-06-18 09:30:00Z]
        },
        overrides
      )

    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end

  test "renders a drop from a public domain to anonymous visitors", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Hive"), "visibility" => "public"})

    drop = insert_drop!(domain)

    {:ok, _view, html} = live(conn, ~p"/drops/#{drop.number}")

    assert html =~ "Slack workspace management moved to Ops"
    assert html =~ ~s(data-part="metadata-card")
    assert html =~ "Metadata"
    assert html =~ "Source"
    assert html =~ "Published"
    assert html =~ "v0.25.0"
    assert html =~ domain.name
    assert html =~ "Open original"
  end

  test "redirects old internal id URLs to the public number URL", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Hive"), "visibility" => "public"})

    drop = insert_drop!(domain)
    expected_path = "/drops/#{drop.number}"

    assert {:error, {:redirect, %{to: ^expected_path}}} = live(conn, ~p"/drops/#{drop.id}")
  end

  test "redirects anonymous visitors away from drops in a private domain", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Hive"), "visibility" => "private"})

    drop = insert_drop!(domain)

    assert {:error, {:redirect, %{to: "/drops"}}} = live(conn, ~p"/drops/#{drop.number}")
  end

  test "shows the version chip when present", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Hive"), "visibility" => "public"})

    drop = insert_drop!(domain, %{version: "v4.7.0"})

    {:ok, _view, html} = live(conn, ~p"/drops/#{drop.number}")

    assert html =~ "v4.7.0"
  end

  test "renders sanitized feed markup for changelog drops", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Cache"), "visibility" => "public"})

    drop =
      insert_drop!(domain, %{
        source_type: :rss,
        external_id: "https://tuist.dev/changelog/cache-upload",
        title: "Cache upload access controls",
        body: """
        <p>Teams can switch to <strong>CI and account tokens only</strong> for cache uploads.</p>
        <img src="/marketing/images/changelog/cache-upload.png" alt="Cache upload controls" onerror="alert(1)">
        <a href="javascript:alert(1)" onclick="alert(1)">bad link</a>
        <script>alert(1)</script>
        """,
        url: "https://tuist.dev/changelog/cache-upload",
        version: nil
      })

    {:ok, _view, html} = live(conn, ~p"/drops/#{drop.number}")

    assert html =~
             "<p>Teams can switch to <strong>CI and account tokens only</strong> for cache uploads.</p>"

    assert html =~ ~s(src="https://tuist.dev/marketing/images/changelog/cache-upload.png")
    assert html =~ ~s(alt="Cache upload controls")
    refute html =~ "onerror"
    refute html =~ "javascript:"
    refute html =~ "<script>"
    refute html =~ "alert(1)"

    assert {:ok, data} = advertised_open_graph_data(html)

    assert data.description ==
             "Teams can switch to CI and account tokens only for cache uploads. Cache upload controls bad link"
  end

  test "advertises an OpenGraph image with drop-specific context", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Slack",
        project_id: project.id,
        visibility: "public"
      })

    drop = insert_drop!(domain)

    {:ok, _view, html} = live(conn, ~p"/drops/#{drop.number}")

    assert {:ok, data} = advertised_open_graph_data(html)
    assert data.id == "drop-#{drop.number}"
    assert data.section_label == "Drop · GitHub release · v0.25.0"
    assert data.highlights == ["Project: Hive", "Domain: Slack", "Jun 18, 2026"]
  end

  test "redirects when the drop does not exist", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/drops"}}} =
             live(conn, ~p"/drops/999999999")
  end

  defp advertised_open_graph_data(html) do
    with [_, image] <- Regex.run(~r/property="og:image" content="([^"]+)"/, html),
         %URI{query: query} when is_binary(query) <- URI.parse(image),
         %{"token" => token} <- URI.decode_query(query) do
      OpenGraph.verify_token(HiveWeb.Endpoint, token)
    else
      _other -> {:error, :missing_open_graph_image}
    end
  end
end
