defmodule HiveWeb.SettingsLive.MeadowsTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.GitHub.Repositories
  alias HiveWeb.SettingsLive.Meadows

  test "redirects guests to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings/meadows")
  end

  test "redirects signed-in contributors" do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "contributor@example.com",
        provider: "test",
        provider_uid: "contributor"
      })

    Mimic.stub(Auth, :member?, fn ^user -> false end)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        signed_in?: true,
        current_user: user,
        product_name: "Hive",
        flash: %{}
      }
    }

    assert {:ok, socket} = Meadows.mount(%{}, %{}, socket)
    assert {:redirect, %{to: "/login"}} = socket.redirected
  end

  test "renders the meadows settings page for signed-in users", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/settings/meadows")

    assert html =~ "Meadows"
    assert html =~ "Add meadow"
    assert html =~ "No meadows configured"
  end

  test "renders the new meadow modal", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, _view, html} = live(conn, ~p"/settings/meadows")

    assert html =~ ~s(id="new-meadow-modal")
    assert html =~ "New meadow"
    assert html =~ "Visibility"
    assert html =~ "GitHub repository"
  end

  test "loads repositories when the modal opens and creates a meadow from the selection", %{
    conn: conn
  } do
    {conn, _user} = sign_in(conn, "alice@example.com")

    {:ok, view, html} = live(conn, ~p"/settings/meadows")
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

    {:ok, view, _html} = live(conn, ~p"/settings/meadows")

    html =
      render_submit(view, "save", %{
        "meadow" => %{"name" => String.duplicate("a", 121)}
      })

    assert html =~ "should be at most 120 character(s)"
    refute html =~ "%{count}"
  end
end
