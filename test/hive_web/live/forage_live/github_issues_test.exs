defmodule HiveWeb.ForageLive.GitHubIssuesTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Forage
  alias Hive.Meadows

  defp unique, do: System.unique_integer([:positive])

  defp create_meadow!(attrs) do
    {:ok, meadow} = Meadows.create_meadow(attrs)
    meadow
  end

  defp seed_issue!(meadow, opts) do
    repository = hd(meadow.github_repositories)

    Forage.reconcile_repository_github_issues(repository, [
      %{
        number: Keyword.fetch!(opts, :number),
        title: Keyword.fetch!(opts, :title),
        body: Keyword.get(opts, :body)
      }
    ])

    repository
  end

  test "redirects guests when no public meadow/repo pair exists", %{conn: conn} do
    suffix = unique()

    create_meadow!(%{
      name: "atlas-#{suffix}",
      visibility: "private",
      github_repository_owner: "owner#{suffix}",
      github_repository_name: "atlas#{suffix}",
      github_repository_visibility: "public"
    })

    assert {:error, {:redirect, %{to: "/forage/feature-requests"}}} =
             live(conn, ~p"/forage/github-issues")
  end

  test "renders cached issues for a guest when a public meadow/repo pair exists", %{conn: conn} do
    suffix = unique()

    meadow =
      create_meadow!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(meadow, number: 7, title: "Crash on launch", body: "Detail")

    {:ok, _view, html} = follow_default_filter(conn, ~p"/forage/github-issues")

    assert html =~ "GitHub issues"
    assert html =~ "Crash on launch"
    assert html =~ "owner#{suffix}/hive#{suffix}"
  end

  test "shows the empty state when a member has no meadows with repositories", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")

    {:ok, _view, html} = follow_default_filter(conn, ~p"/forage/github-issues")

    assert html =~ "No open issues to show"
  end

  test "the bare URL redirects to one with the default state=open filter", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")

    assert {:error, {:live_redirect, %{to: target}}} =
             live(conn, ~p"/forage/github-issues")

    assert target =~ "filter_state_op="
    assert target =~ "filter_state_val=open"
  end

  test "lands on state=open and shows the State chip", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    meadow =
      create_meadow!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(meadow, number: 1, title: "Still open")

    {:ok, _view, html} = follow_default_filter(conn, ~p"/forage/github-issues")

    assert html =~ "Still open"
    assert html =~ "State"
    assert html =~ "Open"
  end

  test "filters issues by meadow through URL params", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    meadow_a =
      create_meadow!(%{
        name: "meadow-a-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-a-#{suffix}",
        github_repository_visibility: "public"
      })

    meadow_b =
      create_meadow!(%{
        name: "meadow-b-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-b-#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(meadow_a, number: 1, title: "Issue for A")
    seed_issue!(meadow_b, number: 2, title: "Issue for B")

    {:ok, _view, html} =
      live(
        conn,
        ~p"/forage/github-issues?filter_state_op===&filter_state_val=open&filter_meadow_op===&filter_meadow_val=#{meadow_a.id}"
      )

    assert html =~ "Issue for A"
    refute html =~ "Issue for B"
  end

  test "filters issues by repository through URL params", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    meadow_a =
      create_meadow!(%{
        name: "meadow-a-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-a-#{suffix}",
        github_repository_visibility: "public"
      })

    meadow_b =
      create_meadow!(%{
        name: "meadow-b-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-b-#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(meadow_a, number: 1, title: "Issue for A")
    seed_issue!(meadow_b, number: 2, title: "Issue for B")

    repository_b = hd(meadow_b.github_repositories)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/forage/github-issues?filter_state_op===&filter_state_val=open&filter_repository_op===&filter_repository_val=#{repository_b.id}"
      )

    refute html =~ "Issue for A"
    assert html =~ "Issue for B"
  end

  test "showing only closed issues hides open ones", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    meadow =
      create_meadow!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(meadow, number: 1, title: "Open one")

    {:ok, _view, html} =
      live(conn, ~p"/forage/github-issues?filter_state_op===&filter_state_val=closed")

    refute html =~ "Open one"
  end

  test "hides issues from private repos when viewed by a guest", %{conn: conn} do
    suffix = unique()

    private_meadow =
      create_meadow!(%{
        name: "atlas-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "atlas#{suffix}",
        github_repository_visibility: "private"
      })

    seed_issue!(private_meadow, number: 1, title: "Private issue", body: "Sensitive")

    public_meadow =
      create_meadow!(%{
        name: "public-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "public#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(public_meadow, number: 2, title: "Public issue", body: "Open")

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
