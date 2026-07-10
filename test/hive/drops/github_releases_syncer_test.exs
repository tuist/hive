defmodule Hive.Drops.GitHubReleasesSyncerTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  import Ecto.Query

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.DomainClassificationWorker
  alias Hive.Drops.GitHubReleasesSyncer
  alias Hive.Domains
  alias Hive.Forage.GitHubIssue
  alias Hive.GitHub.Client
  alias Hive.GitHub.Issues
  alias Hive.GitHub.Releases
  alias Hive.Projects

  defp unique, do: System.unique_integer([:positive])

  defp setup_repository! do
    suffix = unique()

    {:ok, domain} =
      Domains.create_domain(%{
        name: "release-syncer-#{suffix}",
        project_id: create_project!().id,
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}",
        github_repository_visibility: "public"
      })

    github_repository_for_domain!(domain)
  end

  defp create_project! do
    {:ok, project} = Projects.create_project(%{name: "Project #{unique()}"})
    project
  end

  test "upserts one drop for each generated release item" do
    repository = setup_repository!()
    owner = repository.owner
    name = repository.name
    parent = self()

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Releases, :list_releases, fn %{owner: ^owner, name: ^name} ->
      {:ok,
       [
         %Releases{
           tag_name: "v1.2.0",
           body: """
           ## What's changed

           - Project cache warmups finish faster in ##{41}
           - Generated project paths now stay stable: https://github.com/#{owner}/#{name}/pull/42
           """,
           html_url: "https://github.com/#{owner}/#{name}/releases/tag/v1.2.0",
           published_at: "2026-06-18T09:30:00Z"
         }
       ]}
    end)

    stub(Issues, :get_issue, fn
      %{owner: ^owner, name: ^name}, 41 ->
        {:ok,
         %Issues{
           number: 41,
           title: "Project cache warmups finish faster",
           body: "Warmups now reuse existing cache metadata before planning work.",
           state: "closed"
         }}

      %{owner: ^owner, name: ^name}, 42 ->
        {:ok,
         %Issues{
           number: 42,
           title: "Generated project paths stay stable",
           body: "Generated projects now preserve path casing across machines.",
           state: "closed"
         }}
    end)

    item_generator = fn %{owner: ^owner, name: ^name},
                        %Releases{tag_name: "v1.2.0"} = release,
                        [] ->
      send(parent, {:generated_release_items, release.body})

      {:ok,
       [
         %{
           title: "Project cache warmups finish faster",
           body: "Warmups now reuse existing cache metadata before planning work.",
           source_urls: [
             "https://github.com/#{owner}/#{name}/releases/tag/v1.2.0",
             "https://github.com/#{owner}/#{name}/issues/41"
           ]
         },
         %{
           title: "Generated project paths stay stable",
           body: "Generated projects now preserve path casing across machines.",
           source_urls: ["https://github.com/#{owner}/#{name}/pull/42"]
         }
       ]}
    end

    assert :ok = GitHubReleasesSyncer.sync_now(item_generator: item_generator)
    assert_received {:generated_release_items, body}
    assert body =~ "What's changed"

    drops = Repo.all(from drop in Drop, order_by: [asc: drop.title])

    assert Enum.map(drops, & &1.title) == [
             "Generated project paths stay stable",
             "Project cache warmups finish faster"
           ]

    assert Enum.all?(drops, &(&1.source_type == :github_release))
    assert Enum.all?(drops, &(&1.github_repository_id == repository.id))
    assert Enum.all?(drops, &(&1.version == "v1.2.0"))
    assert Enum.all?(drops, &(&1.published_at == ~U[2026-06-18 09:30:00Z]))

    assert Enum.map(drops, & &1.url) == [
             "https://github.com/#{owner}/#{name}/pull/42",
             "https://github.com/#{owner}/#{name}/issues/41"
           ]

    assert Enum.all?(
             drops,
             &String.starts_with?(&1.external_id, "#{owner}/#{name}@v1.2.0:")
           )

    assert drops |> Enum.map(& &1.external_id) |> Enum.uniq() |> length() == 2

    github_issues = Repo.all(from issue in GitHubIssue, order_by: [asc: issue.number])

    assert Enum.map(github_issues, &{&1.number, &1.state}) == [
             {41, :closed},
             {42, :closed}
           ]

    drops_by_title =
      drops
      |> Repo.preload(:github_issues)
      |> Map.new(fn drop -> {drop.title, drop.github_issues} end)

    assert drops_by_title
           |> Map.fetch!("Generated project paths stay stable")
           |> Enum.map(& &1.number) == [42]

    assert drops_by_title
           |> Map.fetch!("Project cache warmups finish faster")
           |> Enum.map(& &1.number) == [41]

    issue_41 = Enum.find(github_issues, &(&1.number == 41))
    assert [release_drop] = Drops.list_release_drops_for_github_issue(issue_41)
    assert release_drop.version == "v1.2.0"
    assert release_drop.title == "Project cache warmups finish faster"

    drop_ids = Enum.map(drops, & &1.id) |> Enum.sort()

    enqueued_ids =
      all_enqueued(worker: DomainClassificationWorker)
      |> Enum.map(& &1.args["drop_id"])
      |> Enum.sort()

    assert enqueued_ids == drop_ids

    assert :ok =
             GitHubReleasesSyncer.sync_now(
               item_generator: fn _repository, _release, _opts ->
                 send(parent, :unexpected_release_regeneration)
                 {:ok, []}
               end
             )

    refute_received :unexpected_release_regeneration
  end

  test "does not create a drop when the generator returns no items" do
    repository = setup_repository!()
    owner = repository.owner
    name = repository.name
    parent = self()

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Releases, :list_releases, fn %{owner: ^owner, name: ^name} ->
      {:ok,
       [
         %Releases{
           tag_name: "v1.2.1",
           body: "This release updates internal packaging metadata.",
           published_at: "2026-06-18T10:30:00Z"
         }
       ]}
    end)

    item_generator = fn %{owner: ^owner, name: ^name}, %Releases{tag_name: "v1.2.1"}, [] ->
      send(parent, :empty_release_generated)
      {:ok, []}
    end

    assert :ok = GitHubReleasesSyncer.sync_now(item_generator: item_generator)
    assert_received :empty_release_generated

    assert Repo.aggregate(Drop, :count) == 0
    assert [] = all_enqueued(worker: DomainClassificationWorker)

    assert :ok =
             GitHubReleasesSyncer.sync_now(
               item_generator: fn _repository, _release, _opts ->
                 send(parent, :unexpected_empty_release_regeneration)
                 {:ok, []}
               end
             )

    refute_received :unexpected_empty_release_regeneration
  end

  test "does not create a drop when release item generation is skipped" do
    repository = setup_repository!()
    owner = repository.owner
    name = repository.name

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Releases, :list_releases, fn %{owner: ^owner, name: ^name} ->
      {:ok,
       [
         %Releases{
           tag_name: "v1.2.2",
           body: "See https://github.com/#{owner}/#{name}/issues/41",
           published_at: "2026-06-18T10:30:00Z"
         }
       ]}
    end)

    assert :ok =
             GitHubReleasesSyncer.sync_now(
               item_generator: fn _repository, _release, _opts -> :skipped end
             )

    assert Repo.aggregate(Drop, :count) == 0
    assert [] = all_enqueued(worker: DomainClassificationWorker)
  end

  test "stops the sync cycle after a hard provider failure" do
    repository = setup_repository!()
    owner = repository.owner
    name = repository.name
    parent = self()

    stub(Client, :config, fn -> {:ok, %Client.Config{}} end)

    stub(Releases, :list_releases, fn %{owner: ^owner, name: ^name} ->
      {:ok,
       [
         %Releases{
           tag_name: "v1.2.3",
           body: "See https://github.com/#{owner}/#{name}/issues/41",
           published_at: "2026-06-18T10:30:00Z"
         },
         %Releases{
           tag_name: "v1.2.4",
           body: "See https://github.com/#{owner}/#{name}/issues/42",
           published_at: "2026-06-18T11:30:00Z"
         }
       ]}
    end)

    error =
      ReqLLM.Error.API.Request.exception(
        reason: "Provider response error (402): Together API error: credit_limit",
        status: 402,
        response_body: "402 Payment Required",
        request_body: "full prompt body"
      )

    item_generator = fn _repository, release, _opts ->
      send(parent, {:generated_release, release.tag_name})
      {:error, error}
    end

    assert :ok = GitHubReleasesSyncer.sync_now(item_generator: item_generator)

    assert_received {:generated_release, "v1.2.3"}
    refute_received {:generated_release, "v1.2.4"}
  end

  test "perform/1 maps skipped syncs to success" do
    stub(Client, :config, fn -> {:error, {:not_configured, [:private_key]}} end)

    assert :ok = GitHubReleasesSyncer.perform(%Oban.Job{})
  end
end
