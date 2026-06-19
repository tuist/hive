defmodule Hive.Drops.ReleaseBodyRewriterTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.ReleaseBodyRewriter
  alias Hive.Meadows

  setup :verify_on_exit!

  test "rewrites the body and stamps rewritten_at when agents are enabled" do
    {:ok, meadow} =
      Meadows.create_meadow(%{
        name: "Hive",
        visibility: "public",
        github_repository_owner: "tuist",
        github_repository_name: "hive"
      })

    [repository | _] = meadow.github_repositories

    raw_body = """
    Highlights for the v0.25.0 release.

    - Move Slack management to ops (#51) by @pepicrft
    - Touch up empty states (#50)
    """

    {:ok, drop} =
      Drops.upsert_release_drop(%{
        github_repository_id: repository.id,
        source_type: :github_release,
        external_id: "tuist/hive@v0.25.0",
        title: "v0.25.0",
        body: raw_body,
        url: "https://github.com/tuist/hive/releases/tag/v0.25.0",
        published_at: ~U[2026-06-18 09:00:00Z]
      })

    Hive.Agents
    |> stub(:enabled?, fn -> true end)

    runner = fn input ->
      assert input.repository == "tuist/hive"
      assert input.release.tag == "v0.25.0"
      assert input.release.url == "https://github.com/tuist/hive/releases/tag/v0.25.0"
      assert input.release.body =~ "Move Slack management"

      {:ok,
       %{
         body: """
         You can now manage Slack workspaces from the Ops surface,
         and Forage tables now show a clearer empty state when no
         items match the active filter.
         """
       }}
    end

    assert {:ok, %Drop{} = updated} = ReleaseBodyRewriter.rewrite(drop, runner: runner)
    assert updated.body =~ "Slack workspaces"
    refute updated.body =~ "#51"
    assert %DateTime{} = updated.rewritten_at
    assert updated.raw_body == raw_body
  end

  test "returns :skipped when agents are disabled" do
    {:ok, _meadow} = Meadows.create_meadow(%{name: "Hive", visibility: "public"})

    {:ok, drop} =
      Drops.upsert_release_drop(%{
        source_type: :github_release,
        external_id: "tuist/hive@v0.0.1",
        title: "v0.0.1",
        body: "Initial release.",
        url: "https://github.com/tuist/hive/releases/tag/v0.0.1"
      })

    Hive.Agents
    |> stub(:enabled?, fn -> false end)

    assert {:ok, :skipped} = ReleaseBodyRewriter.rewrite(drop)
  end

  test "returns :skipped when the drop has already been rewritten" do
    {:ok, _meadow} = Meadows.create_meadow(%{name: "Hive", visibility: "public"})

    {:ok, drop} =
      Drops.upsert_release_drop(%{
        source_type: :github_release,
        external_id: "tuist/hive@v0.0.2",
        title: "v0.0.2",
        body: "Initial release.",
        url: "https://github.com/tuist/hive/releases/tag/v0.0.2"
      })

    {:ok, rewritten} = Drops.mark_rewritten(drop, "Rewritten body.")

    Hive.Agents
    |> stub(:enabled?, fn -> true end)

    runner = fn _ -> flunk("runner should not be called for already-rewritten drops") end

    assert {:ok, :skipped} = ReleaseBodyRewriter.rewrite(rewritten, runner: runner)
  end
end
