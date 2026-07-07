defmodule Hive.Forage.IntakeTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Domains
  alias Hive.Forage.FeatureRequest
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.Intake
  alias Hive.Forage.IntakeSettings
  alias Hive.GitHub.Issues
  alias Hive.Projects

  defp user(email \\ "intake@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: email,
        provider: "test",
        provider_uid: email
      })

    user
  end

  defp collaborator do
    {:ok, user} =
      Accounts.update_user_role(user("collaborator-intake@example.com"), :collaborator)

    user
  end

  defp repository! do
    suffix = System.unique_integer([:positive])
    {:ok, project} = Projects.create_project(%{name: "Intake #{suffix}"})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Intake #{suffix}",
        project_id: project.id,
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}"
      })

    github_repository_for_domain!(domain)
  end

  describe "config/1" do
    test "defaults to local Hive items" do
      assert Intake.config([]) == %{
               destination: :hive_item,
               github_repository: nil
             }
    end

    test "normalizes GitHub issue configuration" do
      assert Intake.config(
               destination: "github_issue",
               github_repository: "Tuist/Hive"
             ) == %{
               destination: :github_issue,
               github_repository: %{owner: "tuist", name: "hive"}
             }
    end
  end

  describe "create/3" do
    test "creates a local Hive forage item by default" do
      assert {:ok, result} =
               Intake.create(
                 %{
                   "type" => "feature_request",
                   "title" => "Dark mode",
                   "description" => "Customers want a darker dashboard theme."
                 },
                 user()
               )

      assert result.destination == :hive_item
      assert result.hive_path == "/forage/items/manual/#{result.source_record.id}"
      assert result.external_url == nil

      assert [%FeatureRequest{title: "Dark mode"}] = Repo.all(FeatureRequest)
    end

    test "returns changeset errors for invalid local item attributes" do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Intake.create(
                 %{"type" => "feature_request", "title" => "", "description" => "x"},
                 user()
               )
    end

    test "creates a GitHub issue and stores it in the forage cache" do
      repository = repository!()

      expect(Issues, :create_issue, fn ^repository, attrs, [request: :stubbed] ->
        assert attrs.title == "Dark mode"

        assert attrs.body ==
                 "Customers want a darker dashboard theme.\n\n---\nSlack thread: https://slack.example/archives/C/p1"

        assert attrs.labels == ["enhancement"]

        {:ok,
         %Issues{
           number: 42,
           title: attrs.title,
           body: attrs.body,
           state: "open",
           html_url: "https://github.com/#{repository.owner}/#{repository.name}/issues/42"
         }}
      end)

      assert {:ok, result} =
               Intake.create(
                 %{
                   "type" => "feature_request",
                   "title" => "Dark mode",
                   "description" => "Customers want a darker dashboard theme.",
                   "source_label" => "Slack thread",
                   "source_url" => "https://slack.example/archives/C/p1"
                 },
                 user("member-intake@example.com"),
                 config: [
                   destination: :github_issue,
                   github_repository: "#{repository.owner}/#{repository.name}"
                 ],
                 github: [request: :stubbed]
               )

      assert result.destination == :github_issue
      assert result.external_label == "#42"

      assert result.external_url ==
               "https://github.com/#{repository.owner}/#{repository.name}/issues/42"

      assert result.hive_path == "/forage/items/github-issue/#{result.source_record.id}"

      assert [%GitHubIssue{number: 42, title: "Dark mode"}] = Repo.all(GitHubIssue)
    end

    test "uses persisted intake settings by default" do
      repository = repository!()

      assert {:ok, %IntakeSettings{destination: :github_issue}} =
               Intake.settings()
               |> Intake.update_settings(%{
                 "destination" => "github_issue",
                 "github_repository_id" => repository.id
               })

      expect(Issues, :create_issue, fn ^repository, attrs, [request: :persisted_settings] ->
        assert attrs.labels == ["bug"]

        {:ok,
         %Issues{
           number: 43,
           title: attrs.title,
           body: attrs.body,
           state: "open",
           html_url: "https://github.com/#{repository.owner}/#{repository.name}/issues/43"
         }}
      end)

      assert {:ok, result} =
               Intake.create(
                 %{
                   "type" => "bug_report",
                   "title" => "Keyboard shortcuts",
                   "description" => "Power users want shortcuts for triage actions."
                 },
                 user("persisted-intake@example.com"),
                 github: [request: :persisted_settings]
               )

      assert result.destination == :github_issue
      assert result.external_label == "#43"
    end

    test "requires a configured repository for GitHub issue destinations" do
      assert {:error, :github_repository_not_configured} =
               Intake.create(
                 %{
                   "type" => "feature_request",
                   "title" => "Dark mode",
                   "description" => "Customers want a darker dashboard theme."
                 },
                 user("missing-repo-intake@example.com"),
                 config: [destination: :github_issue]
               )
    end

    test "requires an organization member for GitHub issue destinations" do
      repository = repository!()

      assert {:error, :unauthorized} =
               Intake.create(
                 %{
                   "type" => "feature_request",
                   "title" => "Dark mode",
                   "description" => "Customers want a darker dashboard theme."
                 },
                 collaborator(),
                 config: [
                   destination: :github_issue,
                   github_repository: "#{repository.owner}/#{repository.name}"
                 ]
               )
    end
  end
end
