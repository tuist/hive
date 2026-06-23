defmodule HiveWeb.ProjectLive.ShowTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Domains
  alias Hive.Domains.Domain
  alias Hive.Domains.GitHubRepository
  alias Hive.GitHub.Repositories
  alias Hive.Projects
  alias Hive.Projects.Webhooks
  alias Hive.Repo

  test "renders a public project's repositories and domains", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        name: "Hive",
        description: "Agentic domains.",
        visibility: "public"
      })

    {:ok, _domain} =
      Domains.create_domain(%{
        name: "Hive",
        project_id: project.id,
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Hive"
    assert html =~ "Agentic domains."
    assert html =~ "tuist/hive"
    refute html =~ "Link repository"
    refute html =~ "Link domain"
    refute html =~ "Remove repository"
    refute html =~ "Remove domain"
    refute html =~ "New webhook"
  end

  test "members can update a project", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Save project"

    html =
      render_submit(view, "save", %{
        "project" => %{
          "name" => "Hive Cloud",
          "description" => "Planning and orchestration.",
          "visibility" => "private"
        }
      })

    assert html =~ "Hive Cloud"
    assert html =~ "Planning and orchestration."
  end

  test "members can delete a project after confirming its name", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Kura", visibility: "public"})

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "Delete project"

    assert {:error, {:live_redirect, %{to: "/projects"}}} =
             render_submit(view, "delete_project", %{"name" => "Kura"})
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

  test "renders the empty state when the project has no domains", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{name: "Kura", visibility: "public"})

    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}")

    assert html =~ "No domains defined"
  end

  test "members can remove a repository from a project", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})

    {:ok, _domain} =
      Domains.create_domain(%{
        name: "Cache",
        project_id: project.id,
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    repository = Repo.get_by!(GitHubRepository, owner: "tuist", name: "hive")

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "tuist/hive"
    assert html =~ "Remove repository"

    html = render_click(view, "remove_repository", %{"id" => repository.id})

    refute html =~ "tuist/hive"
    assert Repo.get(GitHubRepository, repository.id) == nil
  end

  test "members can link a repository to a project", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Link repository"
    refute html =~ "tuist/hive"

    Mimic.stub(Repositories, :list_accessible_repositories, fn ->
      {:ok, [%Repositories{owner: "tuist", name: "hive", description: "Agentic domains"}]}
    end)

    Mimic.allow(Repositories, self(), view.pid)

    html = render_hook(view, "link_repository_modal_open_change", %{"open" => true})
    assert html =~ "tuist/hive"
    refute html =~ "link-repository-visibility"

    assert render_click(view, "select_link_repository", %{
             "owner" => "tuist",
             "name" => "hive",
             "description" => "Agentic domains"
           }) =~ "tuist/hive"

    html =
      render_submit(view, "link_repository", %{
        "repository" => %{"owner" => "tuist", "name" => "hive"}
      })

    assert html =~ "tuist/hive"

    repository = Repo.get_by!(GitHubRepository, owner: "tuist", name: "hive")
    assert repository.project_id == project.id
  end

  test "members can unlink a domain from a project", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, domain} = Domains.create_domain(%{name: "Cache", project_id: project.id})

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Cache"
    assert html =~ "Remove domain"

    html = render_click(view, "remove_domain", %{"id" => domain.id})

    refute html =~ ~s(/domains/#{domain.id})
    assert Repo.get!(Domain, domain.id)
    assert Projects.get_project!(project.id).domains == []
  end

  test "members can link an existing domain to a project", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, domain} = Domains.create_domain(%{name: "Cache", description: "Build cache."})

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Link domain"
    assert html =~ "Cache"

    html = render_submit(view, "link_domain", %{"link_domain" => %{"domain_id" => domain.id}})

    assert html =~ ~s(/domains/#{domain.id})
    assert html =~ "Build cache."
    assert Enum.map(Projects.get_project!(project.id).domains, & &1.id) == [domain.id]
  end

  test "members can create a project webhook", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "Webhooks"
    assert html =~ "New webhook"

    html =
      render_submit(view, "create_webhook", %{
        "webhook" => %{"name" => "Grafana prod", "source" => "grafana"}
      })

    assert html =~ "Grafana prod"
    assert html =~ "Webhook URL"
    assert html =~ "/webhooks/projects/#{project.id}/grafana/hwh_"
    assert [_webhook] = Webhooks.list_for_project(project)
  end

  test "members can delete a project webhook", %{conn: conn} do
    {conn, _user} = sign_in(conn, "member@example.com")
    {:ok, project} = Projects.create_project(%{name: "Hive", visibility: "public"})
    {:ok, {webhook, _}} = Webhooks.create(project, %{"name" => "G", "source" => "grafana"})

    {:ok, view, html} = live(conn, ~p"/projects/#{project.id}")
    assert html =~ "G"

    html = render_click(view, "delete_webhook", %{"id" => webhook.id})

    refute html =~ "last used"
    assert Webhooks.list_for_project(project) == []
  end
end
