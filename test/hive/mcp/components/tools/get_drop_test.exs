defmodule Hive.MCP.Components.Tools.GetDropTest do
  use Hive.MCPToolCase

  alias Hive.Drops
  alias Hive.MCP.Components.Tools.GetDrop
  alias Hive.Domains
  alias Hive.Forage
  alias Hive.GitHub.Issues
  alias Hive.Projects

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
  end

  defp insert_drop!(domain, attrs) do
    {:ok, drop} = Drops.upsert_drop(attrs)
    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end

  test "returns the drop when visible to the user" do
    user = mcp_user()
    domain = create_domain!(%{name: "Hive", visibility: "public"})

    drop =
      insert_drop!(domain, %{
        source_type: :rss,
        external_id: "ext-1",
        title: "Changelog v1",
        body: "Body",
        url: "https://example.com/changelog/1"
      })

    response = GetDrop.call(mcp_conn(user), %{"id" => drop.id}) |> response_json()

    assert response["drop"]["id"] == drop.id
    assert response["drop"]["title"] == "Changelog v1"
  end

  test "returns linked GitHub issue forage items" do
    user = mcp_user()

    domain =
      create_domain!(%{
        name: "Hive",
        visibility: "public",
        github_repository_owner: "tuist",
        github_repository_name: "hive",
        github_repository_visibility: "public"
      })

    repository = github_repository_for_domain!(domain)

    {:ok, issue} =
      Forage.upsert_repository_github_issue(repository, %Issues{
        number: 41,
        title: "Ship release graph",
        body: "Drops should point back to the forage item they addressed.",
        state: "closed"
      })

    drop =
      insert_drop!(domain, %{
        source_type: :github_release,
        external_id: "release-1",
        title: "Release graph",
        url: "https://github.com/tuist/hive/releases/tag/v1.2.0",
        version: "v1.2.0"
      })

    Drops.replace_drop_github_issues(drop, [issue.id])

    response = GetDrop.call(mcp_conn(user), %{"id" => drop.id}) |> response_json()

    assert [
             %{
               "number" => 41,
               "state" => "closed",
               "title" => "Ship release graph",
               "url" => "https://github.com/tuist/hive/issues/41"
             }
           ] = response["drop"]["github_issues"]
  end

  test "returns not_found when the drop is linked only to a private domain the user cannot see" do
    user = mcp_user("outsider@external.example")
    {:ok, user} = user |> Ecto.Changeset.change(role: :collaborator) |> Hive.Repo.update()

    domain = create_domain!(%{name: "Hive", visibility: "private"})

    drop =
      insert_drop!(domain, %{
        source_type: :rss,
        external_id: "ext-1",
        title: "Hidden",
        url: "https://example.com/hidden"
      })

    response = GetDrop.call(mcp_conn(user), %{"id" => drop.id}) |> response_json()

    assert response["error"] == "not_found"
  end
end
