defmodule HiveWeb.DropsLive.ShowTest do
  use HiveWeb.ConnCase, async: true

  alias Hive.Drops
  alias Hive.Domains
  alias Hive.Projects

  defp unique_domain_name(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

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

  defp insert_drop!(domain, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          source_type: :github_release,
          external_id: "tuist/hive@v0.25.0#slack-#{System.unique_integer([:positive])}",
          title: "Slack workspace management moved to Ops",
          body:
            "Admins now manage connected Slack workspaces from the Ops surface at `/ops/slack`.",
          url: "https://github.com/tuist/hive/releases/tag/v0.25.0",
          version: "v0.25.0",
          published_at: ~U[2026-06-18 09:30:00Z]
        },
        overrides
      )

    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end

  test "renders a drop from a public domain to anonymous visitors", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Hive"), "visibility" => "public"})

    drop = insert_drop!(domain)

    {:ok, _view, html} = live(conn, ~p"/drops/#{drop.id}")

    assert html =~ "Slack workspace management moved to Ops"
    assert html =~ "v0.25.0"
    assert html =~ domain.name
    assert html =~ "Open original"
  end

  test "redirects anonymous visitors away from drops in a private domain", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Hive"), "visibility" => "private"})

    drop = insert_drop!(domain)

    assert {:error, {:redirect, %{to: "/drops"}}} = live(conn, ~p"/drops/#{drop.id}")
  end

  test "shows the version chip when present", %{conn: conn} do
    domain = create_domain!(%{"name" => unique_domain_name("Hive"), "visibility" => "public"})

    drop = insert_drop!(domain, %{version: "v4.7.0"})

    {:ok, _view, html} = live(conn, ~p"/drops/#{drop.id}")

    assert html =~ "v4.7.0"
  end

  test "redirects when the drop does not exist", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/drops"}}} =
             live(conn, ~p"/drops/00000000-0000-0000-0000-000000000000")
  end
end
