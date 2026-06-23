defmodule HiveWeb.ProjectLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Projects

  test "lists public projects to anonymous visitors", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, _} = Projects.create_project(%{name: "Atlas", visibility: "private"})

    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "Hive"
    assert html =~ ~s(/projects/#{project.id}/drops/atom.xml)
    assert html =~ ~s(/projects/#{project.id}/drops/rss.xml)
    refute html =~ "Atlas"
    refute html =~ "Add project"
  end

  test "members see private projects too", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, _} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, _} = Projects.create_project(%{name: "Atlas", visibility: "private"})

    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "Hive"
    assert html =~ "Atlas"
    assert html =~ "Add project"
  end

  test "members can create projects", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")

    {:ok, view, html} = live(conn, ~p"/projects")
    assert html =~ "Add project"

    html =
      render_submit(view, "create", %{
        "project" => %{
          "name" => "Noora",
          "description" => "Tuist design system.",
          "visibility" => "public"
        }
      })

    assert html =~ "Noora"
    assert html =~ "Tuist design system."
  end

  test "orders Tuist projects in the product order", %{conn: conn} do
    {:ok, atlas} = Projects.create_project(%{name: "Atlas", visibility: "public"})
    {:ok, hive} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, tuist} = Projects.create_project(%{name: "Tuist", visibility: "public"})
    {:ok, kura} = Projects.create_project(%{name: "Kura", visibility: "public"})
    {:ok, noora} = Projects.create_project(%{name: "Noora", visibility: "public"})
    {:ok, once} = Projects.create_project(%{name: "Once", visibility: "public"})

    {:ok, _view, html} = live(conn, ~p"/projects")

    assert project_position(html, atlas) < project_position(html, hive)
    assert project_position(html, hive) < project_position(html, tuist)
    assert project_position(html, tuist) < project_position(html, kura)
    assert project_position(html, kura) < project_position(html, noora)
    assert project_position(html, noora) < project_position(html, once)
  end

  test "renders the empty state when no projects exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "No projects yet"
  end

  defp project_position(html, project) do
    {position, _length} = :binary.match(html, ~s(href="/projects/#{project.id}"))
    position
  end
end
