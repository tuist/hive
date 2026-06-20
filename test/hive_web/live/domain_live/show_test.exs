defmodule HiveWeb.DomainLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Domains

  test "shows a public domain to anonymous visitors in read-only mode", %{conn: conn} do
    {:ok, domain} = Domains.create_domain(%{"name" => "Hive", "visibility" => "public"})

    {:ok, _view, html} = live(conn, ~p"/domains/#{domain.id}")

    assert html =~ "Hive"
    refute html =~ "Save domain"
    refute html =~ "Webhooks"
  end

  test "redirects anonymous visitors away from a private domain", %{conn: conn} do
    {:ok, domain} = Domains.create_domain(%{"name" => "Hive", "visibility" => "private"})

    assert {:error, {:redirect, %{to: "/domains"}}} =
             live(conn, ~p"/domains/#{domain.id}")
  end

  test "redirects contributors away from a private domain", %{conn: conn} do
    {conn, user} = sign_in(conn, "contributor@example.com")
    Mimic.stub(Auth, :member?, fn ^user -> false end)
    {:ok, domain} = Domains.create_domain(%{"name" => "Hive", "visibility" => "private"})

    assert {:error, {:redirect, %{to: "/domains"}}} =
             live(conn, ~p"/domains/#{domain.id}")
  end

  test "renders a domain detail page for signed-in members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Hive",
        description: "Domain orchestration",
        visibility: "private",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, _view, html} = live(conn, ~p"/domains/#{domain.id}")

    assert html =~ "Hive"
    assert html =~ "Domain orchestration"
    assert html =~ "Private"
    assert html =~ "tuist/hive"
    assert html =~ "Save domain"
  end

  test "updates domain fields", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, domain} = Domains.create_domain(%{name: "Atlas"})

    {:ok, view, _html} = live(conn, ~p"/domains/#{domain.id}")

    html =
      view
      |> form("#edit-domain-form",
        domain: %{
          name: "Atlas",
          description: "Private planning.",
          visibility: "private",
          github_repository_owner: "",
          github_repository_name: ""
        }
      )
      |> render_submit()

    assert html =~ "Private planning."
    assert html =~ "Private"
  end

  test "loads repositories on dropdown open and replaces the domain repository", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Hive",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, view, html} = live(conn, ~p"/domains/#{domain.id}")
    refute html =~ "tuist/tuist"

    Mimic.stub(Repositories, :list_accessible_repositories, fn ->
      {:ok, [%Repositories{owner: "tuist", name: "tuist", description: "Tuist monorepo"}]}
    end)

    Mimic.allow(Repositories, self(), view.pid)

    html = render_hook(view, "repository_dropdown_open_change", %{"open" => true})
    assert html =~ "tuist/tuist"

    assert render_click(view, "select_repository", %{
             "owner" => "tuist",
             "name" => "tuist",
             "description" => "Tuist monorepo"
           }) =~ "tuist/tuist"

    html =
      view
      |> form("#edit-domain-form",
        domain: %{
          name: "Hive",
          visibility: "public",
          github_repository_owner: "tuist",
          github_repository_name: "tuist"
        }
      )
      |> render_submit()

    assert html =~ "tuist/tuist"
  end

  test "creates a webhook from the modal form", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, domain} = Domains.create_domain(%{name: "Hive"})

    {:ok, view, _html} = live(conn, ~p"/domains/#{domain.id}")

    html =
      render_submit(view, "create_webhook", %{
        "webhook" => %{"name" => "Grafana prod", "source" => "grafana"}
      })

    assert html =~ "Grafana prod"
    assert html =~ "Webhook URL"
    assert [_webhook] = Hive.Domains.Webhooks.list_for_domain(domain)
  end

  test "deletes a domain when the typed name matches and redirects to the index", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, domain} = Domains.create_domain(%{name: "Hive"})

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
    {:ok, domain} = Domains.create_domain(%{name: "Hive"})

    {:ok, view, _html} = live(conn, ~p"/domains/#{domain.id}")

    view
    |> form("#delete-domain-form", %{"name" => "wrong"})
    |> render_submit()

    assert [%{name: "Hive"}] = Domains.list_domains()
  end

  test "deletes a webhook", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, domain} = Domains.create_domain(%{name: "Hive"})

    {:ok, {webhook, _}} =
      Hive.Domains.Webhooks.create(domain, %{"name" => "G", "source" => "grafana"})

    {:ok, view, _html} = live(conn, ~p"/domains/#{domain.id}")

    render_click(view, "delete_webhook", %{"id" => webhook.id})

    assert Hive.Domains.Webhooks.list_for_domain(domain) == []
  end
end
