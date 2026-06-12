defmodule Hive.MeadowsTest do
  use Hive.DataCase, async: true

  alias Hive.Meadows
  alias Hive.Meadows.GitHubRepository
  alias Hive.Meadows.Meadow
  alias Hive.Meadows.MeadowRepository

  describe "change_meadow/2" do
    test "is valid with a name" do
      changeset = Meadows.change_meadow(%Meadow{}, %{name: "Hive"})

      assert changeset.valid?
      assert get_field(changeset, :visibility) == :public
    end

    test "requires a name" do
      changeset = Meadows.change_meadow(%Meadow{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
    end

    test "rejects unknown visibility" do
      changeset = Meadows.change_meadow(%Meadow{}, %{name: "Hive", visibility: "internal"})

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:visibility]
    end

    test "requires repository owner and name together" do
      owner_changeset =
        Meadows.change_meadow(%Meadow{}, %{
          name: "Hive",
          github_repository_owner: "tuist"
        })

      name_changeset =
        Meadows.change_meadow(%Meadow{}, %{
          name: "Hive",
          github_repository_name: "hive"
        })

      refute owner_changeset.valid?
      refute name_changeset.valid?
      assert {"can't be blank", _} = owner_changeset.errors[:github_repository_name]
      assert {"can't be blank", _} = name_changeset.errors[:github_repository_owner]
    end

    test "normalizes GitHub repository fields" do
      changeset =
        Meadows.change_meadow(%Meadow{}, %{
          name: "Hive",
          github_repository_owner: " Tuist ",
          github_repository_name: " Hive "
        })

      assert get_change(changeset, :github_repository_owner) == "tuist"
      assert get_change(changeset, :github_repository_name) == "hive"
    end
  end

  describe "create_meadow/1" do
    test "creates a meadow without a repository" do
      assert {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})

      assert meadow.name == "Hive"
      assert meadow.visibility == :public
      assert meadow.github_repositories == []
    end

    test "creates a private meadow" do
      assert {:ok, meadow} = Meadows.create_meadow(%{name: "Atlas", visibility: "private"})

      assert meadow.visibility == :private
    end

    test "creates a meadow with a GitHub repository" do
      assert {:ok, meadow} =
               Meadows.create_meadow(%{
                 name: "Hive",
                 description: "Meadow orchestration",
                 github_repository_owner: "Tuist",
                 github_repository_name: "Hive"
               })

      assert meadow.description == "Meadow orchestration"
      assert [%GitHubRepository{owner: "tuist", name: "hive"}] = meadow.github_repositories
      assert Repo.aggregate(MeadowRepository, :count) == 1
    end

    test "allows several meadows to share one repository" do
      assert {:ok, _} =
               Meadows.create_meadow(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "monorepo"
               })

      assert {:ok, _} =
               Meadows.create_meadow(%{
                 name: "Forge",
                 github_repository_owner: "tuist",
                 github_repository_name: "monorepo"
               })

      assert Repo.aggregate(GitHubRepository, :count) == 1
      assert Repo.aggregate(MeadowRepository, :count) == 2
    end

    test "rejects duplicate meadow names" do
      assert {:ok, _} = Meadows.create_meadow(%{name: "Hive"})

      assert {:error, changeset} = Meadows.create_meadow(%{name: "Hive"})

      assert {"has already been taken", _} = changeset.errors[:name]
    end

    test "returns a changeset for invalid repository fields" do
      assert {:error, changeset} =
               Meadows.create_meadow(%{
                 name: "Hive",
                 github_repository_owner: "-tuist",
                 github_repository_name: "hive"
               })

      assert {"must be a valid GitHub owner", _} = changeset.errors[:github_repository_owner]
      assert Repo.aggregate(Meadow, :count) == 0
    end
  end

  describe "list_meadows/0" do
    test "returns meadows ordered by name with repositories preloaded" do
      assert {:ok, _} =
               Meadows.create_meadow(%{
                 name: "Forge",
                 github_repository_owner: "tuist",
                 github_repository_name: "forge"
               })

      assert {:ok, _} = Meadows.create_meadow(%{name: "Atlas"})

      assert [atlas, forge] = Meadows.list_meadows()
      assert atlas.name == "Atlas"
      assert forge.name == "Forge"
      assert [%GitHubRepository{name: "forge"}] = forge.github_repositories
    end
  end

  describe "get_meadow!/1" do
    test "returns a meadow with repositories preloaded" do
      assert {:ok, meadow} =
               Meadows.create_meadow(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert meadow = Meadows.get_meadow!(meadow.id)
      assert [%GitHubRepository{owner: "tuist", name: "hive"}] = meadow.github_repositories
    end
  end

  describe "update_meadow/2" do
    test "updates meadow fields" do
      assert {:ok, meadow} = Meadows.create_meadow(%{name: "Atlas"})

      assert {:ok, meadow} =
               Meadows.update_meadow(meadow, %{
                 name: "Atlas Cloud",
                 description: "Internal meadow planning.",
                 visibility: "private"
               })

      assert meadow.name == "Atlas Cloud"
      assert meadow.description == "Internal meadow planning."
      assert meadow.visibility == :private
    end

    test "replaces a meadow repository" do
      assert {:ok, meadow} =
               Meadows.create_meadow(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert {:ok, meadow} =
               Meadows.update_meadow(meadow, %{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "tuist"
               })

      assert [%GitHubRepository{owner: "tuist", name: "tuist"}] = meadow.github_repositories
      assert Repo.aggregate(MeadowRepository, :count) == 1
    end

    test "clears a meadow repository when repository fields are empty" do
      assert {:ok, meadow} =
               Meadows.create_meadow(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert {:ok, meadow} =
               Meadows.update_meadow(meadow, %{
                 name: "Hive",
                 github_repository_owner: "",
                 github_repository_name: ""
               })

      assert meadow.github_repositories == []
      assert Repo.aggregate(MeadowRepository, :count) == 0
    end

    test "keeps repositories when repository fields are omitted" do
      assert {:ok, meadow} =
               Meadows.create_meadow(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert {:ok, meadow} =
               Meadows.update_meadow(meadow, %{name: "Hive app", visibility: "private"})

      assert meadow.name == "Hive app"
      assert meadow.visibility == :private
      assert [%GitHubRepository{owner: "tuist", name: "hive"}] = meadow.github_repositories
    end
  end
end
