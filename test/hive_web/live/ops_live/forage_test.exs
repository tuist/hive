defmodule HiveWeb.OpsLive.ForageTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Accounts
  alias Hive.Audit.Activity
  alias Hive.Forage.Intake
  alias Hive.Forage.IntakeSettings
  alias Hive.Projects
  alias Hive.Repo

  test "redirects anonymous visitors to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login?return_to=/ops/forage"}}} =
             live(conn, ~p"/ops/forage")
  end

  test "redirects non-admins away from forage intake management", %{conn: conn} do
    {conn, user} = sign_in(conn, "member-forage-ops@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :member)

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/ops/forage")
  end

  test "renders forage intake settings for admins", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-forage-ops@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)

    assert {:ok, _view, html} = live(conn, ~p"/ops/forage")

    assert html =~ ~s(id="ops-forage")
    assert html =~ "Intake destination"
    assert html =~ "Hive-managed item"
    assert html =~ "GitHub issue"
    refute html =~ "GitHub repository"
    refute html =~ "GitHub labels"
  end

  test "shows repository controls only for GitHub issue intake", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-forage-repository-controls@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)

    {:ok, view, html} = live(conn, ~p"/ops/forage")

    refute html =~ "GitHub repository"

    html =
      render_change(view, "validate", %{
        "forage_intake_settings" => %{
          "destination" => "github_issue",
          "github_repository_id" => IntakeSettings.empty_github_repository_id_value()
        }
      })

    assert html =~ "GitHub repository"
    assert html =~ "Choose repository"
  end

  test "updates the intake destination", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-forage-save@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)
    {:ok, project} = Projects.create_project(%{name: "Hive"})

    {:ok, repository} =
      Projects.create_repository_for_project(project, %{
        "owner" => "tuist",
        "name" => "hive"
      })

    {:ok, view, _html} = live(conn, ~p"/ops/forage")

    html =
      render_submit(view, "save", %{
        "forage_intake_settings" => %{
          "destination" => "github_issue",
          "github_repository_id" => repository.id
        }
      })

    assert html =~ "Forage intake updated."

    assert %IntakeSettings{
             destination: :github_issue,
             github_repository_id: github_repository_id
           } = Intake.settings()

    assert github_repository_id == repository.id

    assert %Activity{interface: "dashboard"} =
             Repo.get_by!(Activity, action: "forage_intake_settings.updated")
  end

  test "clears the repository placeholder value before saving", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-forage-clear@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)

    {:ok, view, _html} = live(conn, ~p"/ops/forage")

    html =
      render_submit(view, "save", %{
        "forage_intake_settings" => %{
          "destination" => "hive_item",
          "github_repository_id" => IntakeSettings.empty_github_repository_id_value()
        }
      })

    assert html =~ "Forage intake updated."
    assert %IntakeSettings{destination: :hive_item, github_repository_id: nil} = Intake.settings()
  end

  test "renders repositories alphabetically by full name", %{conn: conn} do
    {conn, user} = sign_in(conn, "admin-forage-sort@example.com")
    {:ok, _user} = Accounts.update_user_role(user, :admin)
    {:ok, project} = Projects.create_project(%{name: "Repository sorting"})

    {:ok, _repository} =
      Projects.create_repository_for_project(project, %{
        "owner" => "tuist",
        "name" => "zeta"
      })

    {:ok, _repository} =
      Projects.create_repository_for_project(project, %{
        "owner" => "apple",
        "name" => "alpha"
      })

    {:ok, view, _html} = live(conn, ~p"/ops/forage")

    html =
      render_change(view, "validate", %{
        "forage_intake_settings" => %{
          "destination" => "github_issue",
          "github_repository_id" => IntakeSettings.empty_github_repository_id_value()
        }
      })

    assert html =~ "apple/alpha"
    assert html =~ "tuist/zeta"
    assert :binary.match(html, "apple/alpha") < :binary.match(html, "tuist/zeta")
  end
end
