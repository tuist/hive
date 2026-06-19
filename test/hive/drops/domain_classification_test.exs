defmodule Hive.Drops.DomainClassificationTest do
  use Hive.DataCase, async: true

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.DomainClassification
  alias Hive.Domains

  defp create_domain!(name, attrs \\ %{}) do
    {:ok, domain} = Domains.create_domain(Map.merge(%{name: name, visibility: "public"}, attrs))
    domain
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

  test "links every candidate domain when the LLM is unavailable" do
    a = create_domain!("Alpha-#{System.unique_integer([:positive])}")
    b = create_domain!("Bravo-#{System.unique_integer([:positive])}")

    drop = insert_rss_drop!()

    assert {:ok, ids} =
             DomainClassification.classify(drop.id, agents_enabled?: fn -> false end)

    assert Enum.sort(ids) == Enum.sort([a.id, b.id])

    drop = Repo.preload(Repo.get!(Drop, drop.id), :domains)
    assert Enum.map(drop.domains, & &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])
    refute is_nil(drop.classified_at)
  end

  test "keeps only domain ids the agent picked from the candidate set" do
    a = create_domain!("Alpha-#{System.unique_integer([:positive])}")
    _b = create_domain!("Bravo-#{System.unique_integer([:positive])}")
    drop = insert_rss_drop!()

    runner = fn _input -> {:ok, %{domain_ids: [a.id, "not-a-domain"]}} end

    assert {:ok, [chosen]} =
             DomainClassification.classify(drop.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert chosen == a.id

    drop = Repo.preload(Repo.get!(Drop, drop.id), :domains)
    assert Enum.map(drop.domains, & &1.id) == [a.id]
  end

  test "no candidates leaves classified_at nil so the sweeper retries" do
    drop = insert_rss_drop!()

    assert {:ok, []} = DomainClassification.classify(drop.id, agents_enabled?: fn -> false end)
    drop = Repo.get!(Drop, drop.id)
    assert is_nil(drop.classified_at)
  end
end
