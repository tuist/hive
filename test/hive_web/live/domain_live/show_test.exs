defmodule HiveWeb.DomainLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Auth
  alias Hive.Domains
  alias Hive.Projects

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = put_project_id(attrs, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  defp put_project_id(attrs, project_id) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put_new(attrs, "project_id", project_id)
    else
      Map.put_new(attrs, :project_id, project_id)
    end
  end

  test "shows a public domain to anonymous visitors in read-only mode", %{conn: conn} do
    domain = create_domain!(%{"name" => "Hive", "visibility" => "public"})

    {:ok, _view, html} = live(conn, ~p"/domains/#{domain.id}")

    assert html =~ "Hive"
    refute html =~ "Save domain"
    refute html =~ "Webhooks"
  end

  test "redirects anonymous visitors away from a private domain", %{conn: conn} do
    domain = create_domain!(%{"name" => "Hive", "visibility" => "private"})

    assert {:error, {:redirect, %{to: "/domains"}}} =
             live(conn, ~p"/domains/#{domain.id}")
  end

  test "redirects contributors away from a private domain", %{conn: conn} do
    {conn, user} = sign_in(conn, "contributor@example.com")
    Mimic.stub(Auth, :member?, fn ^user -> false end)
    domain = create_domain!(%{"name" => "Hive", "visibility" => "private"})

    assert {:error, {:redirect, %{to: "/domains"}}} =
             live(conn, ~p"/domains/#{domain.id}")
  end

  test "renders a domain detail page for signed-in members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    domain =
      create_domain!(%{
        name: "Hive",
        description: "Domain orchestration",
        visibility: "private",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, _view, html} = live(conn, ~p"/domains/#{domain.id}")

    assert html =~ "Hive"
    assert html =~ "Domain orchestration"
    assert html =~ "Save domain"
    refute html =~ "Webhooks"
    refute html =~ "Visibility"
    refute html =~ "GitHub repository"
    refute html =~ "tuist/hive"
  end

  test "updates domain fields", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    domain = create_domain!(%{name: "Atlas"})

    {:ok, view, _html} = live(conn, ~p"/domains/#{domain.id}")

    html =
      view
      |> form("#edit-domain-form",
        domain: %{
          name: "Atlas",
          description: "Planning workflows."
        }
      )
      |> render_submit()

    assert html =~ "Planning workflows."
  end

  test "domain edit form does not expose project, visibility, or repository controls", %{
    conn: conn
  } do
    {conn, _user} = sign_in(conn, "alice@example.com")

    domain = create_domain!(%{name: "Hive"})
    {:ok, view, html} = live(conn, ~p"/domains/#{domain.id}")

    assert html =~ "Save domain"
    refute html =~ "Visibility"
    refute html =~ "GitHub repository"
    refute has_element?(view, ~s(input[name="domain[project_id]"]))
    refute has_element?(view, ~s(input[name="domain[visibility]"]))
    refute has_element?(view, ~s(input[name="domain[github_repository_owner]"]))
    refute has_element?(view, ~s(input[name="domain[github_repository_name]"]))
  end

  test "deletes a domain when the typed name matches and redirects to the index", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    domain = create_domain!(%{name: "Hive"})

    {:ok, view, html} = live(conn, ~p"/domains/#{domain.id}")
    assert html =~ "Delete domain"

    assert {:error, {:live_redirect, %{to: "/domains"}}} =
             view
             |> form("#delete-domain-form", %{"name" => "Hive"})
             |> render_submit()

    assert Domains.list_domains() == []
  end

  test "does not delete a domain when the typed name does not match", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    domain = create_domain!(%{name: "Hive"})

    {:ok, view, _html} = live(conn, ~p"/domains/#{domain.id}")

    view
    |> form("#delete-domain-form", %{"name" => "wrong"})
    |> render_submit()

    assert [%{name: "Hive"}] = Domains.list_domains()
  end
end
