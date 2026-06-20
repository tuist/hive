defmodule Hive.Drops.GitHubReleasesSyncerTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  import Ecto.Query

  alias Hive.Drops.Drop
  alias Hive.Drops.GitHubReleasesSyncer
  alias Hive.Drops.MeadowClassificationWorker
  alias Hive.GitHub.Client
  alias Hive.GitHub.Releases
  alias Hive.Meadows

  defp unique, do: System.unique_integer([:positive])

  defp setup_repository! do
    suffix = unique()

    {:ok, meadow} =
      Meadows.create_meadow(%{
        name: "release-syncer-#{suffix}",
        visibility: "public",
        github_repository_owner: "owner#{suffix}",
        github_repository_name: "repo#{suffix}",
        github_repository_visibility: "public"
      })

    hd(meadow.project.github_repositories)
  end

  defp start_syncer!(item_generator \\ fn _repository, _release, _opts -> {:ok, []} end) do
    name = :"release_syncer_#{unique()}"

    {:ok, pid} =
      start_supervised(
        {GitHubReleasesSyncer,
         name: name,
         sync_on_start: false,
         interval_ms: :timer.minutes(60),
         item_generator: item_generator}
      )

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Mimic.allow(Client, self(), pid)
    Mimic.allow(Releases, self(), pid)
    {pid, name}
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

    item_generator = fn %{owner: ^owner, name: ^name},
                        %Releases{tag_name: "v1.2.0"} = release,
                        [] ->
      send(parent, {:generated_release_items, release.body})

      {:ok,
       [
         %{
           title: "Project cache warmups finish faster",
           body: "Warmups now reuse existing cache metadata before planning work.",
           source_urls: ["https://github.com/#{owner}/#{name}/issues/41"]
         },
         %{
           title: "Generated project paths stay stable",
           body: "Generated projects now preserve path casing across machines.",
           source_urls: ["https://github.com/#{owner}/#{name}/pull/42"]
         }
       ]}
    end

    {_pid, syncer_name} = start_syncer!(item_generator)
    assert :ok = GitHubReleasesSyncer.sync_now(syncer_name)
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

    drop_ids = Enum.map(drops, & &1.id) |> Enum.sort()

    enqueued_ids =
      all_enqueued(worker: MeadowClassificationWorker)
      |> Enum.map(& &1.args["drop_id"])
      |> Enum.sort()

    assert enqueued_ids == drop_ids
  end

  test "does not create a drop when the generator returns no items" do
    repository = setup_repository!()
    owner = repository.owner
    name = repository.name

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

    {_pid, syncer_name} = start_syncer!()
    assert :ok = GitHubReleasesSyncer.sync_now(syncer_name)

    assert Repo.aggregate(Drop, :count) == 0
    assert [] = all_enqueued(worker: MeadowClassificationWorker)
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

    {_pid, syncer_name} = start_syncer!(fn _repository, _release, _opts -> :skipped end)
    assert :ok = GitHubReleasesSyncer.sync_now(syncer_name)

    assert Repo.aggregate(Drop, :count) == 0
    assert [] = all_enqueued(worker: MeadowClassificationWorker)
  end
end
