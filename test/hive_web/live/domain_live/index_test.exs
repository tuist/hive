defmodule HiveWeb.DomainLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Domains

  test "shows the domains page to anonymous visitors but hides edit controls", %{conn: conn} do
    {:ok, public} = Domains.create_domain(%{"name" => "Public domain", "visibility" => "public"})

    {:ok, _private} =
      Domains.create_domain(%{"name" => "Private domain", "visibility" => "private"})

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ "Public domain"
    refute html =~ "Private domain"
    refute html =~ "Add domain"
    refute html =~ ~s(href="/domains/#{public.id}")
  end

  test "exposes per-row links to the Atom and RSS feeds", %{conn: conn} do
    {:ok, public} = Domains.create_domain(%{"name" => "Public domain", "visibility" => "public"})

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ ~s(href="/domains/#{public.id}/atom.xml")
    assert html =~ ~s(href="/domains/#{public.id}/rss.xml")
  end

  test "shows contributors public domains without edit controls", %{conn: conn} do
    {conn, user} = sign_in(conn, "contributor@example.com")
    Mimic.stub(Auth, :member?, fn ^user -> false end)

    {:ok, _public} = Domains.create_domain(%{"name" => "Public domain", "visibility" => "public"})

    {:ok, _private} =
      Domains.create_domain(%{"name" => "Private domain", "visibility" => "private"})

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ "Public domain"
    refute html =~ "Private domain"
    refute html =~ "Add domain"
  end

  test "renders the domains page for organization members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ "Domains"
    assert html =~ "Add domain"
    assert html =~ "No domains yet"
  end

  test "renders the new domain modal", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ ~s(id="new-domain-modal")
    assert html =~ "New domain"
    assert html =~ "Visibility"
    assert html =~ "GitHub repository"
  end

  test "loads repositories when the modal opens and creates a domain from the selection", %{
    conn: conn
  } do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, html} = live(conn, ~p"/domains")
    refute html =~ "tuist/hive"

    Mimic.stub(Repositories, :list_accessible_repositories, fn ->
      {:ok, [%Repositories{owner: "tuist", name: "hive", description: "Domain orchestration"}]}
    end)

    Mimic.allow(Repositories, self(), view.pid)

    html = render_hook(view, "new_domain_modal_open_change", %{"open" => true})
    assert html =~ "tuist/hive"

    assert render_click(view, "select_repository", %{
             "owner" => "tuist",
             "name" => "hive",
             "description" => "Domain orchestration"
           }) =~ "tuist/hive"

    html =
      render_submit(view, "save", %{
        "domain" => %{
          "name" => "Hive",
          "description" => "Domain orchestration",
          "visibility" => "private",
          "github_repository_owner" => "tuist",
          "github_repository_name" => "hive"
        }
      })

    assert html =~ "Hive"
    assert html =~ "Domain orchestration"
    assert html =~ "Private"
    assert html =~ "tuist/hive"
  end

  test "surfaces validation errors with interpolated bindings", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/domains")

    html =
      render_submit(view, "save", %{
        "domain" => %{"name" => String.duplicate("a", 121)}
      })

    assert html =~ "should be at most 120 character(s)"
    refute html =~ "%{count}"
  end
end
