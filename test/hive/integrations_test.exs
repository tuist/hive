defmodule Hive.IntegrationsTest do
  use Hive.DataCase, async: true

  alias Hive.Integrations
  alias Hive.Integrations.GitHubApp
  alias Hive.Integrations.GitHubRepository

  defp github_app_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Test App",
        webhook_secret: "whsec_test",
        app_id: "12345",
        private_key: "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----",
        installation_id: "67890"
      },
      overrides
    )
  end

  describe "GitHub apps" do
    test "list_github_apps/0 returns all apps ordered by name" do
      {:ok, _} = Integrations.create_github_app(github_app_attrs(%{name: "Zebra"}))
      {:ok, _} = Integrations.create_github_app(github_app_attrs(%{name: "Alpha"}))

      apps = Integrations.list_github_apps()
      assert [%{name: "Alpha"}, %{name: "Zebra"}] = apps
    end

    test "get_github_app/1 returns the app with repositories preloaded" do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "hive"})

      fetched = Integrations.get_github_app(app.id)
      assert fetched.name == "Test App"
      assert length(fetched.repositories) == 1
    end

    test "get_github_app/1 returns nil for non-existent app" do
      assert Integrations.get_github_app(Ecto.UUID.generate()) == nil
    end

    test "create_github_app/1 with valid attrs creates an app" do
      assert {:ok, %GitHubApp{} = app} = Integrations.create_github_app(github_app_attrs())
      assert app.name == "Test App"
      assert app.app_id == "12345"
    end

    test "create_github_app/1 with missing required fields returns error" do
      assert {:error, changeset} = Integrations.create_github_app(%{name: "Incomplete"})
      assert errors_on(changeset).webhook_secret
    end

    test "update_github_app/2 updates the app" do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      {:ok, updated} = Integrations.update_github_app(app, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "delete_github_app/1 deletes the app and its repositories" do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "hive"})

      assert {:ok, _} = Integrations.delete_github_app(app)
      assert Integrations.get_github_app(app.id) == nil
      assert Integrations.list_github_repositories(app) == []
    end
  end

  describe "GitHub repositories" do
    setup do
      {:ok, app} = Integrations.create_github_app(github_app_attrs())
      %{app: app}
    end

    test "add_github_repository/2 creates a repository", %{app: app} do
      assert {:ok, %GitHubRepository{} = repo} =
               Integrations.add_github_repository(app, %{owner: "tuist", repo: "hive"})

      assert repo.owner == "tuist"
      assert repo.repo == "hive"
    end

    test "add_github_repository/2 enforces uniqueness", %{app: app} do
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "hive"})

      assert {:error, changeset} =
               Integrations.add_github_repository(app, %{owner: "tuist", repo: "hive"})

      assert errors_on(changeset).owner
    end

    test "delete_github_repository/1 removes the repository", %{app: app} do
      {:ok, repo} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "hive"})
      assert {:ok, _} = Integrations.delete_github_repository(repo.id)
      assert Integrations.list_github_repositories(app) == []
    end

    test "list_github_repositories/1 returns repos ordered by owner/repo", %{app: app} do
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "tuist", repo: "tuist"})
      {:ok, _} = Integrations.add_github_repository(app, %{owner: "apple", repo: "swift"})

      repos = Integrations.list_github_repositories(app)
      assert [%{owner: "apple", repo: "swift"}, %{owner: "tuist", repo: "tuist"}] = repos
    end

    test "find_monitored_repository/2 finds a monitored repo", %{app: app} do
      suffix = System.unique_integer([:positive])
      owner = "find-owner-#{suffix}"
      repo_name = "find-repo-#{suffix}"
      {:ok, _} = Integrations.add_github_repository(app, %{owner: owner, repo: repo_name})

      assert %GitHubRepository{} = Integrations.find_monitored_repository(owner, repo_name)
    end

    test "find_monitored_repository/2 returns nil for unmonitored repo" do
      assert Integrations.find_monitored_repository(
               "unknown-#{System.unique_integer([:positive])}",
               "repo"
             ) == nil
    end
  end
end
