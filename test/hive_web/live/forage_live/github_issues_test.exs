defmodule HiveWeb.ForageLive.GitHubIssuesTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Forage
  alias Hive.Products

  defp unique, do: System.unique_integer([:positive])

  defp create_product!(attrs) do
    {:ok, product} = Products.create_product(attrs)
    product
  end

  defp seed_issue!(product, opts) do
    repository = hd(product.github_repositories)

    Forage.reconcile_repository_github_issues(repository, [
      %{
        number: Keyword.fetch!(opts, :number),
        title: Keyword.fetch!(opts, :title),
        body: Keyword.get(opts, :body)
      }
    ])

    repository
  end

  test "redirects guests when no public product/repo pair exists", %{conn: conn} do
    suffix = unique()

    create_product!(%{
      name: "atlas-#{suffix}",
      visibility: "private",
      github_repository_owner: "owner#{suffix}",
      github_repository_name: "atlas#{suffix}",
      github_repository_visibility: "public"
    })

    assert {:error, {:redirect, %{to: "/forage/feature-requests"}}} =
             live(conn, ~p"/forage/github-issues")
  end

  test "renders cached issues for a guest when a public product/repo pair exists", %{conn: conn} do
    suffix = unique()

    product =
      create_product!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(product, number: 7, title: "Crash on launch", body: "Detail")

    {:ok, _view, html} = live(conn, ~p"/forage/github-issues")

    assert html =~ "GitHub issues"
    assert html =~ "Crash on launch"
    assert html =~ "owner#{suffix}/hive#{suffix}"
  end

  test "shows the empty state when a member has no products with repositories", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")

    {:ok, _view, html} = live(conn, ~p"/forage/github-issues")

    assert html =~ "No open issues to show"
  end

  test "defaults to the open state filter when the URL has no params", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    product =
      create_product!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(product, number: 1, title: "Still open")

    {:ok, _view, html} = live(conn, ~p"/forage/github-issues")

    assert html =~ "Still open"
    assert html =~ "State"
    assert html =~ "Open"
  end

  test "filters issues by product through URL params", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    product_a =
      create_product!(%{
        name: "product-a-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-a-#{suffix}",
        github_repository_visibility: "public"
      })

    product_b =
      create_product!(%{
        name: "product-b-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-b-#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(product_a, number: 1, title: "Issue for A")
    seed_issue!(product_b, number: 2, title: "Issue for B")

    {:ok, _view, html} =
      live(
        conn,
        ~p"/forage/github-issues?filter_state_op===&filter_state_val=open&filter_product_op===&filter_product_val=#{product_a.id}"
      )

    assert html =~ "Issue for A"
    refute html =~ "Issue for B"
  end

  test "filters issues by repository through URL params", %{conn: conn} do
    {conn, _user} = sign_in(conn, "pedro@tuist.dev")
    suffix = unique()

    product_a =
      create_product!(%{
        name: "product-a-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-a-#{suffix}",
        github_repository_visibility: "public"
      })

    product_b =
      create_product!(%{
        name: "product-b-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo-b-#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(product_a, number: 1, title: "Issue for A")
    seed_issue!(product_b, number: 2, title: "Issue for B")

    repository_b = hd(product_b.github_repositories)

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

    product =
      create_product!(%{
        name: "hive-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(product, number: 1, title: "Open one")

    {:ok, _view, html} =
      live(conn, ~p"/forage/github-issues?filter_state_op===&filter_state_val=closed")

    refute html =~ "Open one"
  end

  test "hides issues from private repos when viewed by a guest", %{conn: conn} do
    suffix = unique()

    private_product =
      create_product!(%{
        name: "atlas-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "atlas#{suffix}",
        github_repository_visibility: "private"
      })

    seed_issue!(private_product, number: 1, title: "Private issue", body: "Sensitive")

    public_product =
      create_product!(%{
        name: "public-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "public#{suffix}",
        github_repository_visibility: "public"
      })

    seed_issue!(public_product, number: 2, title: "Public issue", body: "Open")

    {:ok, _view, html} = live(conn, ~p"/forage/github-issues")

    assert html =~ "Public issue"
    refute html =~ "Private issue"
  end
end
