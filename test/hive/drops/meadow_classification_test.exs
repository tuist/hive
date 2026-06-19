defmodule Hive.Drops.MeadowClassificationTest do
  use Hive.DataCase, async: true

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.MeadowClassification
  alias Hive.Meadows

  defp create_meadow!(name, attrs \\ %{}) do
    {:ok, meadow} = Meadows.create_meadow(Map.merge(%{name: name, visibility: "public"}, attrs))
    meadow
  end

  defp insert_rss_drop!(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          source_type: :rss,
          external_id: "ext-#{System.unique_integer([:positive])}",
          title: "Drop",
          body: "Body",
          url: "https://example.com/drop"
        },
        attrs
      )

    {:ok, drop} = Drops.upsert_drop(attrs)
    drop
  end

  test "links every candidate meadow when the LLM is unavailable" do
    a = create_meadow!("Alpha-#{System.unique_integer([:positive])}")
    b = create_meadow!("Bravo-#{System.unique_integer([:positive])}")

    drop = insert_rss_drop!()

    assert {:ok, ids} =
             MeadowClassification.classify(drop.id, agents_enabled?: fn -> false end)

    assert Enum.sort(ids) == Enum.sort([a.id, b.id])

    drop = Repo.preload(Repo.get!(Drop, drop.id), :meadows)
    assert Enum.map(drop.meadows, & &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])
    refute is_nil(drop.classified_at)
  end

  test "keeps only meadow ids the agent picked from the candidate set" do
    a = create_meadow!("Alpha-#{System.unique_integer([:positive])}")
    _b = create_meadow!("Bravo-#{System.unique_integer([:positive])}")
    drop = insert_rss_drop!()

    runner = fn _input -> {:ok, %{meadow_ids: [a.id, "not-a-meadow"]}} end

    assert {:ok, [chosen]} =
             MeadowClassification.classify(drop.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert chosen == a.id

    drop = Repo.preload(Repo.get!(Drop, drop.id), :meadows)
    assert Enum.map(drop.meadows, & &1.id) == [a.id]
  end

  test "no candidates leaves classified_at nil so the sweeper retries" do
    drop = insert_rss_drop!()

    assert {:ok, []} = MeadowClassification.classify(drop.id, agents_enabled?: fn -> false end)
    drop = Repo.get!(Drop, drop.id)
    assert is_nil(drop.classified_at)
  end
end
