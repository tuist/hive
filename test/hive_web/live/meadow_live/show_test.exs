defmodule HiveWeb.MeadowLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Meadows

  test "shows a public meadow to anonymous visitors in read-only mode", %{conn: conn} do
    {:ok, meadow} = Meadows.create_meadow(%{"name" => "Hive", "visibility" => "public"})

    {:ok, _view, html} = live(conn, ~p"/meadows/#{meadow.id}")

    assert html =~ "Hive"
    refute html =~ "Save meadow"
    refute html =~ "Webhooks"
  end

  test "redirects anonymous visitors away from a private meadow", %{conn: conn} do
    {:ok, meadow} = Meadows.create_meadow(%{"name" => "Hive", "visibility" => "private"})

    assert {:error, {:redirect, %{to: "/meadows"}}} =
             live(conn, ~p"/meadows/#{meadow.id}")
  end

  test "redirects contributors away from a private meadow", %{conn: conn} do
    {conn, user} = sign_in(conn, "contributor@example.com")
    Mimic.stub(Auth, :member?, fn ^user -> false end)
    {:ok, meadow} = Meadows.create_meadow(%{"name" => "Hive", "visibility" => "private"})

    assert {:error, {:redirect, %{to: "/meadows"}}} =
             live(conn, ~p"/meadows/#{meadow.id}")
  end

  test "renders a meadow detail page for signed-in members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, meadow} =
      Meadows.create_meadow(%{
        name: "Hive",
        description: "Meadow orchestration",
        visibility: "private",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, _view, html} = live(conn, ~p"/meadows/#{meadow.id}")

    assert html =~ "Hive"
    assert html =~ "Meadow orchestration"
    assert html =~ "Private"
    assert html =~ "tuist/hive"
    assert html =~ "Save meadow"
  end

  test "updates meadow fields", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, meadow} = Meadows.create_meadow(%{name: "Atlas"})

    {:ok, view, _html} = live(conn, ~p"/meadows/#{meadow.id}")

    html =
      view
      |> form("form[data-part='form']",
        meadow: %{
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

  test "loads repositories on dropdown open and replaces the meadow repository", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, meadow} =
      Meadows.create_meadow(%{
        name: "Hive",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    {:ok, view, html} = live(conn, ~p"/meadows/#{meadow.id}")
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
      |> form("form[data-part='form']",
        meadow: %{
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
    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})

    {:ok, view, _html} = live(conn, ~p"/meadows/#{meadow.id}")

    html =
      render_submit(view, "create_webhook", %{
        "webhook" => %{"name" => "Grafana prod", "source" => "grafana"}
      })

    assert html =~ "Grafana prod"
    assert html =~ "Webhook URL"
    assert [_webhook] = Hive.Meadows.Webhooks.list_for_meadow(meadow)
  end

  test "deletes a webhook", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})

    {:ok, {webhook, _}} =
      Hive.Meadows.Webhooks.create(meadow, %{"name" => "G", "source" => "grafana"})

    {:ok, view, _html} = live(conn, ~p"/meadows/#{meadow.id}")

    render_click(view, "delete_webhook", %{"id" => webhook.id})

    assert Hive.Meadows.Webhooks.list_for_meadow(meadow) == []
  end
end
