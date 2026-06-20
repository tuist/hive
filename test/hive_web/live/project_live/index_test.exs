defmodule HiveWeb.ProjectLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Projects

  test "lists public projects to anonymous visitors", %{conn: conn} do
    {:ok, _} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, _} = Projects.create_project(%{name: "Atlas", visibility: "private"})

    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "Hive"
    refute html =~ "Atlas"
  end

  test "members see private projects too", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, _} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, _} = Projects.create_project(%{name: "Atlas", visibility: "private"})

    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "Hive"
    assert html =~ "Atlas"
  end

  test "orders Tuist projects in the product order", %{conn: conn} do
    {:ok, _} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, _} = Projects.create_project(%{name: "Once", visibility: "public"})
    {:ok, _} = Projects.create_project(%{name: "Tuist", visibility: "public"})
    {:ok, _} = Projects.create_project(%{name: "Atlas", visibility: "public"})

    {:ok, _view, html} = live(conn, ~p"/projects")

    project_names =
      ~r/<h2>([^<]+)<\/h2>/
      |> Regex.scan(html, capture: :all_but_first)
      |> List.flatten()

    assert project_names == ["Tuist", "Atlas", "Hive", "Once"]
  end

  test "renders the empty state when no projects exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "No projects yet"
  end
end
