defmodule Hive.DropsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.DropSource
  alias Hive.Meadows

  describe "upsert_drop/1" do
    test "inserts a drop and upserts an existing one by (source_type, external_id)" do
      attrs = %{
        source_type: :rss,
        external_id: "abc-123",
        title: "Initial title",
        body: "Body v1",
        url: "https://example.com/v1",
        published_at: ~U[2026-06-18 12:00:00Z]
      }

      assert {:ok, %Drop{title: "Initial title"} = drop} = Drops.upsert_drop(attrs)

      assert {:ok, %Drop{title: "Updated title"} = updated} =
               Drops.upsert_drop(%{attrs | title: "Updated title"})

      assert updated.id == drop.id
      assert Repo.aggregate(Drop, :count, :id) == 1
    end
  end

  describe "list_drops/1" do
    test "anonymous viewers only see drops from public meadows" do
      public = create_meadow!(%{name: "Public meadow", visibility: :public})
      private = create_meadow!(%{name: "Private meadow", visibility: :private})

      {:ok, public_drop} = insert_drop(public)
      {:ok, _hidden_drop} = insert_drop(private)

      {drops, meta} = Drops.list_drops(user: nil)

      assert Enum.map(drops, & &1.id) == [public_drop.id]
      assert meta.total_entries == 1
    end

    test "members see drops from every meadow" do
      member = create_member!()
      public = create_meadow!(%{name: "Public", visibility: :public})
      private = create_meadow!(%{name: "Private", visibility: :private})

      {:ok, _public_drop} = insert_drop(public)
      {:ok, _private_drop} = insert_drop(private)

      {drops, _meta} = Drops.list_drops(user: member)

      assert length(drops) == 2
    end

    test "filters by meadow_ids" do
      a = create_meadow!(%{name: "A"})
      b = create_meadow!(%{name: "B"})

      {:ok, drop_a} = insert_drop(a)
      {:ok, _drop_b} = insert_drop(b)

      {drops, _meta} = Drops.list_drops(user: nil, meadow_ids: [a.id])

      assert Enum.map(drops, & &1.id) == [drop_a.id]
    end

    test "filters by source_type and search text" do
      meadow = create_meadow!()
      {:ok, gh_drop} = insert_drop(meadow, %{source_type: :github_release, title: "v1.2.3"})

      {:ok, _rss_drop} =
        insert_drop(meadow, %{
          source_type: :rss,
          external_id: "rss-1",
          title: "Marketing post"
        })

      {drops, _meta} = Drops.list_drops(user: nil, source_type: :github_release)
      assert Enum.map(drops, & &1.id) == [gh_drop.id]

      {drops, _meta} = Drops.list_drops(user: nil, query: "marketing")
      assert length(drops) == 1
    end
  end

  describe "drop_sources" do
    test "creates a source and enforces unique url" do
      assert {:ok, %DropSource{}} =
               Drops.create_drop_source(%{
                 "url" => "https://example.com/feed.atom",
                 "label" => "Example"
               })

      result =
        Drops.create_drop_source(%{"url" => "https://example.com/feed.atom"})

      assert {:error, %Ecto.Changeset{} = changeset} = result
      refute changeset.valid?
      assert changeset.errors |> Keyword.has_key?(:url)
    end

    test "record_source_poll updates timestamps and error state" do
      {:ok, source} = Drops.create_drop_source(%{url: "https://x.test/feed"})

      assert {:ok, polled_ok} = Drops.record_source_poll(source, :ok)
      assert polled_ok.last_polled_at
      assert is_nil(polled_ok.last_error)

      assert {:ok, polled_err} = Drops.record_source_poll(polled_ok, {:error, :timeout})
      assert polled_err.last_error =~ "timeout"
      assert polled_err.last_error_at
    end
  end

  defp create_meadow!(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Meadow #{System.unique_integer([:positive])}"}, attrs)
    {:ok, meadow} = Meadows.create_meadow(attrs)
    meadow
  end

  defp create_member! do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "member-#{System.unique_integer([:positive])}@hive.test",
        provider: "test",
        provider_uid: "member-#{System.unique_integer([:positive])}"
      })

    {:ok, user} = user |> Ecto.Changeset.change(role: :member) |> Repo.update()
    user
  end

  defp insert_drop(meadow, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          source_type: :rss,
          external_id: "ext-#{System.unique_integer([:positive])}",
          title: "Drop",
          body: "Body",
          url: "https://example.com/drop",
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        overrides
      )

    with {:ok, drop} <- Drops.upsert_drop(attrs) do
      Drops.replace_drop_meadows(drop, [meadow.id])
      {:ok, drop}
    end
  end
end
