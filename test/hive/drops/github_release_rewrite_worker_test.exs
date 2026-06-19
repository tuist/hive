defmodule Hive.Drops.GitHubReleaseRewriteWorkerTest do
  use Hive.DataCase, async: true
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.GitHubReleaseRewriteWorker
  alias Hive.Meadows

  describe "enqueue/2" do
    test "returns :skipped when agents are disabled" do
      drop = %Drop{
        id: "11111111-1111-1111-1111-111111111111",
        source_type: :github_release,
        raw_body: "body"
      }

      assert :skipped = GitHubReleaseRewriteWorker.enqueue(drop, agents_enabled?: fn -> false end)
    end

    test "returns :skipped for non-release drops" do
      drop = %Drop{
        id: "11111111-1111-1111-1111-111111111111",
        source_type: :rss,
        raw_body: "body"
      }

      assert :skipped = GitHubReleaseRewriteWorker.enqueue(drop, agents_enabled?: fn -> true end)
    end

    test "returns :skipped when there is no raw_body" do
      drop = %Drop{
        id: "11111111-1111-1111-1111-111111111111",
        source_type: :github_release,
        raw_body: nil
      }

      assert :skipped = GitHubReleaseRewriteWorker.enqueue(drop, agents_enabled?: fn -> true end)
    end

    test "returns :skipped when the drop has already been rewritten" do
      drop = %Drop{
        id: "11111111-1111-1111-1111-111111111111",
        source_type: :github_release,
        raw_body: "body",
        rewritten_at: DateTime.utc_now()
      }

      assert :skipped = GitHubReleaseRewriteWorker.enqueue(drop, agents_enabled?: fn -> true end)
    end

    test "enqueues an Oban job when agents are enabled and the drop is fresh" do
      {:ok, _meadow} = Meadows.create_meadow(%{name: "Hive", visibility: "public"})

      {:ok, drop} =
        Drops.upsert_release_drop(%{
          source_type: :github_release,
          external_id: "tuist/hive@v0.0.3",
          title: "v0.0.3",
          body: "Release notes.",
          url: "https://github.com/tuist/hive/releases/tag/v0.0.3"
        })

      assert {:ok, _job} =
               GitHubReleaseRewriteWorker.enqueue(drop, agents_enabled?: fn -> true end)

      assert_enqueued(
        worker: GitHubReleaseRewriteWorker,
        args: %{"drop_id" => drop.id}
      )
    end
  end

  describe "perform/1" do
    test "returns :ok when the drop no longer exists" do
      job = %Oban.Job{args: %{"drop_id" => "00000000-0000-0000-0000-000000000000"}}
      assert :ok = GitHubReleaseRewriteWorker.perform(job)
    end
  end
end
