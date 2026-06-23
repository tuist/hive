defmodule Hive.DropsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.DropSource
  alias Hive.Domains
  alias Hive.Domains.GitHubRepository
  alias Hive.Projects

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

    test "accepts string-keyed attrs and ignores unknown keys" do
      assert {:ok, %Drop{} = drop} =
               Drops.upsert_drop(%{
                 "source_type" => "github_release",
                 "external_id" => "release-1",
                 "title" => "v1.0.0",
                 "body" => "Release notes",
                 "url" => "https://github.com/tuist/hive/releases/tag/1.0.0",
                 "published_at" => ~U[2026-06-20 12:00:00Z],
                 "unexpected_attribute" => "ignored"
               })

      assert drop.source_type == :github_release
      assert drop.external_id == "release-1"
      assert drop.body == "Release notes"
    end
  end

  describe "list_drops/1" do
    test "anonymous viewers only see drops from public domains" do
      public = create_domain!(%{name: "Public domain", visibility: :public})
      private = create_domain!(%{name: "Private domain", visibility: :private})

      {:ok, public_drop} = insert_drop(public)
      {:ok, _hidden_drop} = insert_drop(private)

      {drops, meta} = Drops.list_drops(user: nil)

      assert Enum.map(drops, & &1.id) == [public_drop.id]
      assert meta.total_entries == 1
    end

    test "members see drops from every domain" do
      member = create_member!()
      public = create_domain!(%{name: "Public", visibility: :public})
      private = create_domain!(%{name: "Private", visibility: :private})

      {:ok, _public_drop} = insert_drop(public)
      {:ok, _private_drop} = insert_drop(private)

      {drops, _meta} = Drops.list_drops(user: member)

      assert length(drops) == 2
    end

    test "filters by domain_ids" do
      a = create_domain!(%{name: "A"})
      b = create_domain!(%{name: "B"})

      {:ok, drop_a} = insert_drop(a)
      {:ok, _drop_b} = insert_drop(b)

      {drops, _meta} = Drops.list_drops(user: nil, domain_ids: [a.id])

      assert Enum.map(drops, & &1.id) == [drop_a.id]
    end

    test "filters by source_type and search text" do
      domain = create_domain!()
      {:ok, gh_drop} = insert_drop(domain, %{source_type: :github_release, title: "v1.2.3"})

      {:ok, _rss_drop} =
        insert_drop(domain, %{
          source_type: :rss,
          external_id: "rss-1",
          title: "Marketing post"
        })

      {drops, _meta} = Drops.list_drops(user: nil, source_type: :github_release)
      assert Enum.map(drops, & &1.id) == [gh_drop.id]

      {drops, _meta} = Drops.list_drops(user: nil, query: "marketing")
      assert length(drops) == 1
    end

    test "keeps source project available when a drop has no domains yet" do
      member = create_member!()
      {:ok, project} = Projects.create_project(%{name: "Noora", visibility: :public})

      repository =
        %GitHubRepository{}
        |> GitHubRepository.changeset(%{
          owner: "tuist",
          name: "noora",
          project_id: project.id
        })
        |> Repo.insert!()

      {:ok, _drop} =
        Drops.upsert_drop(%{
          source_type: :github_release,
          external_id: "tuist/noora@0.82.6",
          title: "Breadcrumb keyboard states",
          url: "https://github.com/tuist/noora/releases/tag/0.82.6",
          github_repository_id: repository.id
        })

      {[drop], _meta} = Drops.list_drops(user: member)

      assert Enum.map(Drops.projects_for_drop(drop), & &1.name) == ["Noora"]
      assert drop.domains == []
    end
  end

  describe "drop_sources" do
    setup do
      {:ok, project} = Hive.Projects.create_project(%{name: "Hive"})
      %{project: project}
    end

    test "creates a source and enforces unique url", %{project: project} do
      assert {:ok, %DropSource{}} =
               Drops.create_drop_source(%{
                 "project_id" => project.id,
                 "url" => "https://example.com/feed.atom",
                 "label" => "Example"
               })

      result =
        Drops.create_drop_source(%{
          "project_id" => project.id,
          "url" => "https://example.com/feed.atom"
        })

      assert {:error, %Ecto.Changeset{} = changeset} = result
      refute changeset.valid?
      assert changeset.errors |> Keyword.has_key?(:url)
    end

    test "record_source_poll updates timestamps and error state", %{project: project} do
      {:ok, source} =
        Drops.create_drop_source(%{project_id: project.id, url: "https://x.test/feed"})

      assert {:ok, polled_ok} = Drops.record_source_poll(source, :ok)
      assert polled_ok.last_polled_at
      assert is_nil(polled_ok.last_error)

      assert {:ok, polled_err} = Drops.record_source_poll(polled_ok, {:error, :timeout})
      assert polled_err.last_error =~ "timeout"
      assert polled_err.last_error_at
    end
  end

  defp create_domain!(attrs \\ %{}) do
    attrs = Map.merge(%{name: "Domain #{System.unique_integer([:positive])}"}, attrs)

    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
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

  defp insert_drop(domain, overrides \\ %{}) do
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
      Drops.replace_drop_domains(drop, [domain.id])
      {:ok, drop}
    end
  end
end
