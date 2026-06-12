defmodule HiveWeb.MeadowLive.IndexTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias Hive.Meadows

  test "shows the meadows page to anonymous visitors but hides edit controls", %{conn: conn} do
    {:ok, _public} = Meadows.create_meadow(%{"name" => "Public meadow", "visibility" => "public"})

    {:ok, _private} =
      Meadows.create_meadow(%{"name" => "Private meadow", "visibility" => "private"})

    {:ok, _view, html} = live(conn, ~p"/meadows")

    assert html =~ "Public meadow"
    refute html =~ "Private meadow"
    refute html =~ "Add meadow"
  end

  test "shows contributors public meadows without edit controls", %{conn: conn} do
    {conn, user} = sign_in(conn, "contributor@example.com")
    Mimic.stub(Auth, :member?, fn ^user -> false end)

    {:ok, _public} = Meadows.create_meadow(%{"name" => "Public meadow", "visibility" => "public"})

    {:ok, _private} =
      Meadows.create_meadow(%{"name" => "Private meadow", "visibility" => "private"})

    {:ok, _view, html} = live(conn, ~p"/meadows")

    assert html =~ "Public meadow"
    refute html =~ "Private meadow"
    refute html =~ "Add meadow"
  end

  test "renders the meadows page for organization members", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/meadows")

    assert html =~ "Meadows"
    assert html =~ "Add meadow"
    assert html =~ "No meadows yet"
  end

  test "renders the new meadow modal", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/meadows")

    assert html =~ ~s(id="new-meadow-modal")
    assert html =~ "New meadow"
    assert html =~ "Visibility"
    assert html =~ "GitHub repository"
  end

  test "loads repositories when the modal opens and creates a meadow from the selection", %{
    conn: conn
  } do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, html} = live(conn, ~p"/meadows")
    refute html =~ "tuist/hive"

    Mimic.stub(Repositories, :list_accessible_repositories, fn ->
      {:ok, [%Repositories{owner: "tuist", name: "hive", description: "Meadow orchestration"}]}
    end)

    Mimic.allow(Repositories, self(), view.pid)

    html = render_hook(view, "new_meadow_modal_open_change", %{"open" => true})
    assert html =~ "tuist/hive"

    assert render_click(view, "select_repository", %{
             "owner" => "tuist",
             "name" => "hive",
             "description" => "Meadow orchestration"
           }) =~ "tuist/hive"

    html =
      render_submit(view, "save", %{
        "meadow" => %{
          "name" => "Hive",
          "description" => "Meadow orchestration",
          "visibility" => "private",
          "github_repository_owner" => "tuist",
          "github_repository_name" => "hive"
        }
      })

    assert html =~ "Hive"
    assert html =~ "Meadow orchestration"
    assert html =~ "Private"
    assert html =~ "tuist/hive"
  end

  test "surfaces validation errors with interpolated bindings", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, _html} = live(conn, ~p"/meadows")

    html =
      render_submit(view, "save", %{
        "meadow" => %{"name" => String.duplicate("a", 121)}
      })

    assert html =~ "should be at most 120 character(s)"
    refute html =~ "%{count}"
  end
end
