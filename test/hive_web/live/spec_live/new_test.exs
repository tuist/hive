defmodule HiveWeb.SpecLive.NewTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Forage
  alias Hive.Domains
  alias Hive.Projects

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  test "redirects guests away from the new spec form", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/specs"}}} = live(conn, ~p"/specs/new")
  end

  test "creates a direct spec", %{conn: conn} do
    {conn, _user} = sign_in(conn, "alice@example.com")
    domain = create_domain!(%{name: "Hive app"})

    {:ok, view, html} = live(conn, ~p"/specs/new")

    assert html =~ "Hive app"
    assert html =~ ~s(id="spec-status")
    assert html =~ ~s(name="spec[status]")
    assert html =~ ~s(id="spec-visibility")
    assert html =~ ~s(name="spec[visibility]")
    assert html =~ ~s(class="noora-dropdown")

    result =
      view
      |> form("form[data-part='form']",
        spec: %{
          title: "GitHub sign-in",
          body: "Add GitHub sign-in for requesters.",
          status: "proposed",
          domain_ids: [domain.id]
        }
      )
      |> render_submit()

    {:ok, _view, html} = follow_redirect(result, conn)

    assert html =~ "GitHub sign-in"
    assert html =~ "Add GitHub sign-in for requesters."
    assert html =~ "Created directly"
    assert html =~ "Hive app"
  end

  test "prefills a spec from a feature request source", %{conn: conn} do
    {conn, user} = sign_in(conn, "alice@example.com")

    {:ok, feature_request} =
      Forage.create_feature_request(
        %{
          "title" => "Dark mode",
          "description" => "Please add a dark theme to the dashboard."
        },
        user
      )

    {:ok, view, html} = live(conn, ~p"/specs/new?source_feature_request_id=#{feature_request.id}")

    assert html =~ "Source: Dark mode"

    result =
      view
      |> form("form[data-part='form']",
        spec: %{
          title: "Dark mode",
          body: "Please add a dark theme to the dashboard.",
          status: "draft",
          source_feature_request_id: feature_request.id
        }
      )
      |> render_submit()

    {:ok, _view, html} = follow_redirect(result, conn)
    assert html =~ "Source: Dark mode"
  end
end
