defmodule Hive.Drops.WeeklyDigestsTest do
  use Hive.DataCase, async: true

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.WeeklyDigest
  alias Hive.Drops.WeeklyDigests
  alias Hive.Domains
  alias Hive.Projects

  @week_start ~D[2026-07-06]

  test "generates one narrated digest from bounded public drops" do
    public_domain = create_domain!("Public", :public)
    private_domain = create_domain!("Private", :private)

    public_drop =
      insert_drop!(public_domain, "Cache controls", ~U[2026-07-08 09:00:00Z], "Public body")

    insert_drop!(
      private_domain,
      "Private operations",
      ~U[2026-07-09 09:00:00Z],
      "Must stay private"
    )

    runner = fn input ->
      send(self(), {:digest_input, input})

      {:ok,
       %{
         title: "The week — connected",
         summary: "Several changes — one direction.",
         body:
           "The week started with [cache controls](/drops/#{public_drop.number}) — then widened."
       }}
    end

    assert {:ok, digest, :published} =
             WeeklyDigests.generate_for_week(@week_start,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert_receive {:digest_input, input}
    assert input.week_start == "2026-07-06"
    assert input.week_end == "2026-07-10"
    assert input.style_sample_urls == WeeklyDigests.style_sample_urls()
    assert [%{title: "Cache controls"}] = input.drops
    refute inspect(input) =~ "Private operations"

    assert digest.status == :published
    assert digest.drop_ids == [public_drop.id]
    assert digest.title == "The week: connected"
    assert digest.summary == "Several changes: one direction."
    refute digest.body =~ "—"
    assert WeeklyDigests.public_path(digest) == "/drops/digest/2026-07-06"
  end

  test "does not spend again for a week that was already evaluated" do
    domain = create_domain!("Public", :public)
    insert_drop!(domain, "First pass", ~U[2026-07-07 09:00:00Z], "Body")

    runner = fn _input ->
      send(self(), :runner_called)
      {:ok, %{title: "Week", summary: "Summary", body: "Narration"}}
    end

    assert {:ok, first, :published} =
             WeeklyDigests.generate_for_week(@week_start,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert_receive :runner_called

    assert {:ok, second, :existing} =
             WeeklyDigests.generate_for_week(@week_start,
               agents_enabled?: fn -> true end,
               runner: fn _input -> flunk("runner should not be called twice") end
             )

    assert second.id == first.id
  end

  test "records an empty week without calling the language model" do
    assert {:ok, digest, :empty} =
             WeeklyDigests.generate_for_week(@week_start,
               runner: fn _input -> flunk("empty weeks should not call the runner") end
             )

    assert digest.status == :empty
    assert WeeklyDigests.list_published() == []
  end

  test "leaves a populated week unclaimed when inference is dormant" do
    domain = create_domain!("Public", :public)
    insert_drop!(domain, "Dormant", ~U[2026-07-07 09:00:00Z], "Body")

    assert :skipped =
             WeeklyDigests.generate_for_week(@week_start,
               agents_enabled?: fn -> false end,
               runner: fn _input -> flunk("runner should stay dormant") end
             )

    refute Repo.get_by(WeeklyDigest, week_start: @week_start)
  end

  test "reclaims a failed week on the next scheduled attempt" do
    domain = create_domain!("Public", :public)
    insert_drop!(domain, "Retry", ~U[2026-07-07 09:00:00Z], "Body")

    assert {:error, :timeout} =
             WeeklyDigests.generate_for_week(@week_start,
               agents_enabled?: fn -> true end,
               runner: fn _input -> {:error, :timeout} end
             )

    assert %WeeklyDigest{status: :failed} = Repo.get_by(WeeklyDigest, week_start: @week_start)

    assert {:ok, digest, :published} =
             WeeklyDigests.generate_for_week(@week_start,
               agents_enabled?: fn -> true end,
               runner: fn _input ->
                 {:ok, %{title: "Recovered", summary: "Summary", body: "Narration"}}
               end
             )

    assert digest.status == :published
    assert digest.title == "Recovered"
  end

  test "selects the latest publishable Monday-to-Friday workweek" do
    assert WeeklyDigests.latest_publishable_week(~U[2026-07-13 08:00:00Z]) ==
             {~D[2026-07-06], ~D[2026-07-10]}

    assert WeeklyDigests.latest_publishable_week(~U[2026-07-17 16:59:59Z]) ==
             {~D[2026-07-06], ~D[2026-07-10]}

    assert WeeklyDigests.latest_publishable_week(~U[2026-07-17 17:00:00Z]) ==
             {~D[2026-07-13], ~D[2026-07-17]}

    assert WeeklyDigests.latest_publishable_week(~U[2026-07-19 08:00:00Z]) ==
             {~D[2026-07-13], ~D[2026-07-17]}
  end

  defp create_domain!(name, visibility) do
    {:ok, project} =
      Projects.create_project(%{
        name: "#{name} project #{System.unique_integer([:positive])}",
        visibility: visibility
      })

    {:ok, domain} =
      Domains.create_domain(%{
        name: "#{name} #{System.unique_integer([:positive])}",
        project_id: project.id,
        visibility: visibility
      })

    domain
  end

  defp insert_drop!(domain, title, published_at, body) do
    drop =
      Repo.insert!(%Drop{
        number: System.unique_integer([:positive]),
        source_type: :rss,
        external_id: "digest-#{System.unique_integer([:positive])}",
        title: title,
        body: body,
        url: "https://example.com/#{System.unique_integer([:positive])}",
        published_at: published_at
      })

    Drops.replace_drop_domains(drop, [domain.id])
    drop
  end
end
