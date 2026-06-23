defmodule HiveWeb.DomainLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.Projects

  test "shows the domains page to anonymous visitors but hides edit controls", %{conn: conn} do
    project = create_project!()

    {:ok, public} =
      Domains.create_domain(%{
        "name" => "Public domain",
        "project_id" => project.id,
        "visibility" => "public"
      })

    {:ok, _private} =
      Domains.create_domain(%{
        "name" => "Private domain",
        "project_id" => project.id,
        "visibility" => "private"
      })

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ "Public domain"
    refute html =~ "Private domain"
    refute html =~ "Add domain"
    refute html =~ ~s(href="/domains/#{public.id}")
  end

  test "exposes per-row links to the Atom and RSS feeds", %{conn: conn} do
    project = create_project!()

    {:ok, public} =
      Domains.create_domain(%{
        "name" => "Public domain",
        "project_id" => project.id,
        "visibility" => "public"
      })

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ ~s(href="/domains/#{public.id}/atom.xml")
    assert html =~ ~s(href="/domains/#{public.id}/rss.xml")
  end

  test "shows contributors public domains without edit controls", %{conn: conn} do
    {conn, user} = sign_in(conn, "contributor@example.com")
    Mimic.stub(Auth, :member?, fn ^user -> false end)
    project = create_project!()

    {:ok, _public} =
      Domains.create_domain(%{
        "name" => "Public domain",
        "project_id" => project.id,
        "visibility" => "public"
      })

    {:ok, _private} =
      Domains.create_domain(%{
        "name" => "Private domain",
        "project_id" => project.id,
        "visibility" => "private"
      })

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
    create_project!(%{name: "Hive"})

    {:ok, _view, html} = live(conn, ~p"/domains")

    assert html =~ ~s(id="new-domain-modal")
    assert html =~ "New domain"
    assert html =~ "Create a reusable domain the team can link to projects."
    assert html =~ "Name"
    assert html =~ "Description"
    refute html =~ ~s(id="new-domain-project")
    refute html =~ ~s(name="domain[project_id]")
    refute html =~ "Visibility"
    refute html =~ "GitHub repository"
  end

  test "creates a reusable domain from the modal form", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/domains")

    html =
      render_submit(view, "save", %{
        "domain" => %{
          "name" => "Hive",
          "description" => "Domain orchestration"
        }
      })

    assert html =~ "Hive"
    assert html =~ "Domain orchestration"
    refute html =~ "tuist/hive"
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

  defp create_project!(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{name: "Project #{System.unique_integer([:positive])}", visibility: "public"},
        attrs
      )

    {:ok, project} = Projects.create_project(attrs)
    project
  end
end
