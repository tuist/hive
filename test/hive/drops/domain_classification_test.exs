defmodule Hive.Drops.DomainClassificationTest do
  use Hive.DataCase, async: true

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.DomainClassification
  alias Hive.Domains
  alias Hive.Projects

  defp create_domain!(name, attrs \\ %{}) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
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

  test "trims drop body and candidate-domain descriptions in the runner input" do
    test_pid = self()

    domain = create_domain!("Alpha-#{System.unique_integer([:positive])}")
    long_description = String.duplicate("a", 400)
    {:ok, _} = Domains.update_domain(domain, %{description: long_description})

    long_body = String.duplicate("b", 2_000)
    drop = insert_rss_drop!(%{body: long_body})

    runner = fn input ->
      send(test_pid, {:input, input})
      {:ok, %{domain_ids: []}}
    end

    assert {:ok, []} =
             DomainClassification.classify(drop.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert_receive {:input, input}

    [candidate] = input.candidate_domains
    assert String.length(candidate.description) == 203
    assert String.ends_with?(candidate.description, "...")

    assert String.length(input.drop.body) == 503
    assert String.ends_with?(input.drop.body, "...")
  end

  test "trims a multibyte drop body without corrupting the last character" do
    test_pid = self()

    _domain = create_domain!("Beta-#{System.unique_integer([:positive])}")
    multibyte = String.duplicate("🎉", 600)
    drop = insert_rss_drop!(%{body: multibyte})

    runner = fn input ->
      send(test_pid, {:input, input})
      {:ok, %{domain_ids: []}}
    end

    assert {:ok, []} =
             DomainClassification.classify(drop.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert_receive {:input, input}
    body = input.drop.body
    assert String.valid?(body)
    assert String.length(body) == 503

    assert body
           |> String.replace_suffix("...", "")
           |> String.graphemes()
           |> Enum.all?(&(&1 == "🎉"))
  end

  test "reuses a classification until source or candidate domain context changes" do
    domain = create_domain!("Cached-#{System.unique_integer([:positive])}")
    drop = insert_rss_drop!()
    test_pid = self()

    runner = fn _input ->
      send(test_pid, :classified)
      {:ok, %{domain_ids: [domain.id]}}
    end

    opts = [agents_enabled?: fn -> true end, runner: runner]

    assert {:ok, [chosen]} = DomainClassification.classify(drop.id, opts)
    assert chosen == domain.id
    assert_received :classified
    assert {:ok, [^chosen]} = DomainClassification.classify(drop.id, opts)
    refute_received :classified

    drop |> Ecto.Changeset.change(body: "Changed release") |> Repo.update!()
    assert {:ok, [^chosen]} = DomainClassification.classify(drop.id, opts)
    assert_received :classified

    {:ok, _} = Domains.update_domain(domain, %{description: "Changed scope"})
    assert {:ok, [^chosen]} = DomainClassification.classify(drop.id, opts)
    assert_received :classified
  end

  for result <- [:selected, :empty] do
    test "restores #{result} classifications when requeued with unchanged model input" do
      assert_restored_after_requeue(unquote(result))
    end
  end

  defp assert_restored_after_requeue(result) do
    domain = create_domain!("Requeued-#{System.unique_integer([:positive])}")
    body = String.duplicate("a", 600)
    drop = insert_rss_drop!(%{body: body})
    ids = if result == :selected, do: [domain.id], else: []

    assert {:ok, ^ids} =
             DomainClassification.classify(drop.id,
               agents_enabled?: fn -> true end,
               runner: fn _ -> {:ok, %{domain_ids: ids}} end
             )

    fingerprint = Repo.get!(Drop, drop.id).classification_fingerprint

    drop
    |> Ecto.Changeset.change(
      body: body <> " [x] done",
      classified_at: nil,
      classification_failure: "llm_credit_limit",
      classification_failed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, ^ids} =
             DomainClassification.classify(drop.id,
               agents_enabled?: fn -> true end,
               runner: fn _ -> flunk("unchanged model input must not spend again") end
             )

    restored = Repo.get!(Drop, drop.id) |> Repo.preload(:domains)
    assert %DateTime{} = restored.classified_at
    assert is_nil(restored.classification_failure)
    assert is_nil(restored.classification_failed_at)
    assert restored.classification_fingerprint == fingerprint
    assert Enum.map(restored.domains, & &1.id) == ids
  end

  test "does not restore a cached result from a stale drop snapshot" do
    _domain = create_domain!("Stale-#{System.unique_integer([:positive])}")
    drop = insert_rss_drop!()
    opts = [agents_enabled?: fn -> true end, runner: fn _ -> {:ok, %{domain_ids: []}} end]
    assert {:ok, []} = DomainClassification.classify(drop.id, opts)
    stale = Repo.get!(Drop, drop.id) |> Repo.preload(:github_repository)
    stale |> Ecto.Changeset.change(title: "Changed input", classified_at: nil) |> Repo.update!()

    assert {:error, :classification_input_changed} =
             DomainClassification.classify_drop(stale,
               agents_enabled?: fn -> true end,
               runner: fn _ -> flunk("must not classify the stale input") end
             )

    assert is_nil(Repo.get!(Drop, drop.id).classified_at)
  end

  test "does not save a model result after its domain context changes" do
    domain = create_domain!("Edited-#{System.unique_integer([:positive])}")
    drop = insert_rss_drop!()

    runner = fn _input ->
      {:ok, _} = Domains.update_domain(domain, %{description: "Updated while classifying"})
      {:ok, %{domain_ids: [domain.id]}}
    end

    assert {:error, :classification_input_changed} =
             DomainClassification.classify(drop.id,
               agents_enabled?: fn -> true end,
               runner: runner
             )

    assert is_nil(Repo.get!(Drop, drop.id).classification_fingerprint)
  end
end
