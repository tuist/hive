defmodule HiveWeb.ForageLive.GitHubIssuesTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.Domains
  alias Hive.Projects
  alias Hive.Repo

  defp unique, do: System.unique_integer([:positive])

  defp create_domain!(attrs) do
    attrs =
      Map.put_new_lazy(attrs, :project_id, fn ->
        {:ok, project} = Projects.create_project(%{name: "Project #{unique()}"})
        project.id
      end)

    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  defp seed_issue!(domain, opts) do
    repository = github_repository_for_domain!(domain)

    Forage.reconcile_repository_github_issues(repository, [
      %{
        number: Keyword.fetch!(opts, :number),
        title: Keyword.fetch!(opts, :title),
        body: Keyword.get(opts, :body)
      }
    ])

    repository
  end

  test "hides private GitHub issues from guests", %{conn: conn} do
    suffix = unique()

    domain =
      create_domain!(%{
        name: "atlas-#{suffix}",
        visibility: "private",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "atlas#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(domain, number: 3, title: "Private crash")

    {:ok, _view, html} = live(conn, ~p"/forage")

    refute html =~ "Private crash"
  end

  test "renders cached issues for a guest when a public domain/repo pair exists", %{conn: conn} do
    suffix = unique()

    domain =
      create_domain!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(domain, number: 7, title: "Crash on launch", body: "Detail")

    {:ok, _view, html} = follow_default_filter(conn, ~p"/forage/github-issues")

    assert html =~ "GitHub issue"
    assert html =~ "Crash on launch"
    assert html =~ "owner#{suffix}/hive#{suffix}"
  end

  test "opens GitHub issues on a dedicated item detail page", %{conn: conn} do
    suffix = unique()

    domain =
      create_domain!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    repository = seed_issue!(domain, number: 42, title: "Crash on launch", body: "Detail")
    issue = Repo.get_by!(GitHubIssue, github_repository_id: repository.id, number: 42)

    {:ok, view, _html} = live(conn, ~p"/forage")

    item_path = "/forage/items/github-issue/#{issue.id}"

    assert {:error, {:live_redirect, %{to: ^item_path}}} =
             view
             |> element("a[data-part='item-title-link']", "Crash on launch")
             |> render_click()

    {:ok, _view, html} = live(conn, ~p"/forage/items/github-issue/#{issue.id}")

    assert html =~ "Crash on launch"
    assert html =~ "Open on GitHub"
    refute html =~ "Add context or feedback with Markdown"
  end

  test "shows the empty state when a member has no domains with repositories", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")

    {:ok, _view, html} = follow_default_filter(conn, ~p"/forage/github-issues")

    assert html =~ "No forage items found"
  end

  test "the legacy source URL redirects to filtered forage", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")

    assert {:error, {:live_redirect, %{to: target}}} =
             live(conn, ~p"/forage/github-issues")

    assert target =~ "/forage?"
    assert target =~ "filter_type_val=github_issue"
  end

  test "lands on state=open and shows the State chip", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    domain =
      create_domain!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(domain, number: 1, title: "Still open")

    {:ok, _view, html} =
      live(
        conn,
        ~p"/forage?filter_type_op===&filter_type_val=github_issue&filter_status_op===&filter_status_val=open"
      )

    assert html =~ "Still open"
    assert html =~ "Status"
    assert html =~ "Open"
  end

  test "filters issues by domain through URL params", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    domain_a =
      create_domain!(%{
        name: "domain-a-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-a-#{suffix}",
        github_repository_visibility: "public"
      })

    domain_b =
      create_domain!(%{
        name: "domain-b-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-b-#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(domain_a, number: 1, title: "Issue for A")
    seed_issue!(domain_b, number: 2, title: "Issue for B")

    {:ok, _view, html} =
      live(
        conn,
        ~p"/forage?filter_type_op===&filter_type_val=github_issue&filter_status_op===&filter_status_val=open&filter_domain_op===&filter_domain_val=#{domain_a.id}"
      )

    assert html =~ "Issue for A"
    refute html =~ "Issue for B"
  end

  test "filters issues by repository through URL params", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    domain_a =
      create_domain!(%{
        name: "domain-a-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-a-#{suffix}",
        github_repository_visibility: "public"
      })

    domain_b =
      create_domain!(%{
        name: "domain-b-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-b-#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(domain_a, number: 1, title: "Issue for A")
    seed_issue!(domain_b, number: 2, title: "Issue for B")

    repository_b = github_repository_for_domain!(domain_b)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/forage?filter_type_op===&filter_type_val=github_issue&filter_status_op===&filter_status_val=open&filter_repository_op===&filter_repository_val=#{repository_b.id}"
      )

    refute html =~ "Issue for A"
    assert html =~ "Issue for B"
  end

  test "showing only closed issues hides open ones", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    domain =
      create_domain!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(domain, number: 1, title: "Open one")

    {:ok, _view, html} =
      live(
        conn,
        ~p"/forage?filter_type_op===&filter_type_val=github_issue&filter_status_op===&filter_status_val=closed"
      )

    refute html =~ "Open one"
  end

  test "hides issues from private repos when viewed by a guest", %{conn: conn} do
    suffix = unique()

    private_domain =
      create_domain!(%{
        name: "atlas-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "atlas#{suffix}",
        github_repository_visibility: "private"
      })

    seed_issue!(private_domain, number: 1, title: "Private issue", body: "Sensitive")

    public_domain =
      create_domain!(%{
        name: "public-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "public#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(public_domain, number: 2, title: "Public issue", body: "Open")

    {:ok, _view, html} = follow_default_filter(conn, ~p"/forage/github-issues")

    assert html =~ "Public issue"
    refute html =~ "Private issue"
  end

  defp follow_default_filter(conn, path) do
    case live(conn, path) do
      {:error, {:live_redirect, %{to: target}}} -> live(conn, target)
      other -> other
    end
  end
end
