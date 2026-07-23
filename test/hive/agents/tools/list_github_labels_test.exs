defmodule Hive.Agents.Tools.ListGitHubLabelsTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Agents.Tools.ListGitHubLabels
  alias Hive.Domains
  alias Hive.Forage.Intake
  alias Hive.GitHub.Issues
  alias Hive.Projects

  test "lists configured labels only when the agent asks for them" do
    suffix = System.unique_integer([:positive])
    {:ok, project} = Projects.create_project(%{name: "Label tool #{suffix}"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Label tool #{suffix}",
        project_id: project.id,
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}"
      })

    repository = github_repository_for_domain!(domain)

    assert {:ok, _settings} =
             Intake.settings()
             |> Intake.update_settings(%{
               "destination" => "github_issue",
               "github_repository_id" => repository.id
             })

    {:ok, requester} =
      Accounts.upsert_from_auth(%{
        email: "label-tool-#{suffix}@example.com",
        provider: "test",
        provider_uid: "label-tool-#{suffix}"
      })

    expect(Issues, :list_labels, fn %{id: repository_id}, [] ->
      assert repository_id == repository.id

      {:ok,
       [
         %{name: "bug", description: String.duplicate("b", 300)},
         %{name: "production", description: nil}
       ]}
    end)

    result =
      ListGitHubLabels.call(%{}, %{assigns: %{requester_user: requester}})

    assert {:ok,
            %{
              labels: [
                %{name: "bug", description: description},
                %{name: "production"}
              ]
            }} = result

    assert String.length(description) == 240
  end

  test "rejects calls without a requester in the tool context" do
    assert {:error, "The Slack user is not linked to a Hive user."} =
             ListGitHubLabels.call(%{}, %{assigns: %{}})
  end
end
