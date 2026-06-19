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

  test "renders the empty state when no projects exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/projects")

    assert html =~ "No projects yet"
  end
end
