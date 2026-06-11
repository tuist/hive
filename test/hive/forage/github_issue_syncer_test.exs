defmodule Hive.Forage.GitHubIssueSyncerTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Forage
  alias Hive.Forage.GitHubIssue
  alias Hive.Forage.GitHubIssueSyncer
  alias Hive.GitHub.Client
  alias Hive.GitHub.Issues
  alias Hive.Products

  defp unique, do: System.unique_integer([:positive])

  defp setup_product! do
    suffix = unique()

    {:ok, product} =
      Products.create_product(%{
        name: "hive-syncer-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "hive#{suffix}",
        github_repository_visibility: "public"
      })

    product
  end

  defp start_syncer! do
    name = :"syncer_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      start_supervised(
        {GitHubIssueSyncer, name: name, sync_on_start: false, interval_ms: :timer.minutes(60)}
      )

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Mimic.allow(Client, self(), pid)
    Mimic.allow(Issues, self(), pid)
    {pid, name}
  end

  test "skips the sync when the GitHub App is not configured" do
    stub(Client, :config, fn -> {:error, {:not_configured, [:app_id]}} end)
    setup_product!()

    {_pid, name} = start_syncer!()

    assert :skipped = GitHubIssueSyncer.sync_now(name)
    assert Repo.aggregate(GitHubIssue, :count) == 0
  end

  test "upserts new issues and deletes issues that disappeared upstream" do
    product = setup_product!()
    repository = hd(product.github_repositories)

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Issues, :list_open_issues, fn ^repository ->
      {:ok,
       [
         %Issues{number: 1, title: "Initial title", body: "Initial body"},
         %Issues{number: 2, title: "Second issue", body: "Body two"}
       ]}
    end)

    {_pid, name} = start_syncer!()
    assert :ok = GitHubIssueSyncer.sync_now(name)

    assert [first, second] = Repo.all(from issue in GitHubIssue, order_by: [asc: issue.number])
    assert first.title == "Initial title"
    assert second.title == "Second issue"

    stub(Issues, :list_open_issues, fn ^repository ->
      {:ok, [%Issues{number: 1, title: "Updated title", body: "Updated body"}]}
    end)

    assert :ok = GitHubIssueSyncer.sync_now(name)

    assert [remaining] = Repo.all(GitHubIssue)
    assert remaining.number == 1
    assert remaining.title == "Updated title"
  end

  test "list_github_issues_for_user/1 returns issues with their product/repo context" do
    product = setup_product!()
    repository = hd(product.github_repositories)

    Forage.reconcile_repository_github_issues(repository, [
      %{number: 1, title: "Hello", body: "World"}
    ])

    assert [{returned_product, returned_repo, issue}] = Forage.list_github_issues_for_user(nil)
    assert returned_product.id == product.id
    assert returned_repo.id == repository.id
    assert issue.title == "Hello"
  end
end
