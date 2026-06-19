defmodule HiveWeb.ProjectLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Meadows
  alias Hive.Projects

  test "renders a public project's repositories and meadows", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        name: "Hive",
        description: "Agentic meadows.",
        visibility: "public"
      })

    {:ok, _meadow} =
      Meadows.create_meadow(%{
        name: "Hive",
        project_id: project.id,
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Hive"
    assert html =~ "Agentic meadows."
    assert html =~ "tuist/hive"
  end

  test "redirects anonymous visitors away from a private project", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{name: "Atlas", visibility: "private"})

    assert {:error, {:redirect, %{to: "/projects"}}} = live(conn, ~p"/projects/#{project.id}")
  end

  test "redirects when the project does not exist", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/projects"}}} =
             live(conn, ~p"/projects/00000000-0000-0000-0000-000000000000")
  end

  test "renders the empty state when the project has no meadows", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Kura", visibility: "public"})

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "No meadows defined"
  end
end
