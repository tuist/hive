defmodule Hive.DomainsTest do
  use Hive.DataCase, async: true

  alias Hive.Domains
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
  alias Hive.Projects.Project

  describe "change_domain/2" do
    test "is valid with a name" do
      changeset = Domains.change_domain(%Domain{}, %{name: "Hive"})

      assert changeset.valid?
      assert get_field(changeset, :visibility) == :public
    end

    test "requires a name" do
      changeset = Domains.change_domain(%Domain{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
    end

    test "rejects unknown visibility" do
      changeset = Domains.change_domain(%Domain{}, %{name: "Hive", visibility: "internal"})

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:visibility]
    end

    test "requires repository owner and name together" do
      owner_changeset =
        Domains.change_domain(%Domain{}, %{
          name: "Hive",
          github_repository_owner: "tuist"
        })

      name_changeset =
        Domains.change_domain(%Domain{}, %{
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
        Domains.change_domain(%Domain{}, %{
          name: "Hive",
          github_repository_owner: " Tuist ",
          github_repository_name: " Hive "
        })

      assert get_change(changeset, :github_repository_owner) == "tuist"
      assert get_change(changeset, :github_repository_name) == "hive"
    end
  end

  describe "create_domain/1" do
    test "auto-bootstraps a project named after the domain" do
      assert {:ok, domain} = Domains.create_domain(%{name: "Hive"})

      assert domain.name == "Hive"
      assert domain.visibility == :public
      assert domain.project.name == "Hive"
      assert domain.project.github_repositories == []
    end

    test "creates a private domain under a private project" do
      assert {:ok, domain} = Domains.create_domain(%{name: "Atlas", visibility: "private"})

      assert domain.visibility == :private
      assert domain.project.visibility == :private
    end

    test "attaches a GitHub repository to the bootstrapped project" do
      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 description: "Domain orchestration",
                 github_repository_owner: "Tuist",
                 github_repository_name: "Hive"
               })

      assert domain.description == "Domain orchestration"

      assert [%GitHubRepository{owner: "tuist", name: "hive"}] =
               domain.project.github_repositories

      assert Repo.aggregate(GitHubRepository, :count) == 1
    end

    test "links a domain to an existing project when project_id is supplied" do
      {:ok, project} =
        Hive.Projects.create_project(%{name: "Tuist", visibility: "public"})

      assert {:ok, cache} =
               Domains.create_domain(%{name: "Cache", project_id: project.id})

      assert {:ok, generated} =
               Domains.create_domain(%{name: "Generated", project_id: project.id})

      assert cache.project.id == project.id
      assert generated.project.id == project.id
    end

    test "rejects duplicate domain names" do
      assert {:ok, _} = Domains.create_domain(%{name: "Hive"})

      assert {:error, changeset} = Domains.create_domain(%{name: "Hive"})

      assert {"has already been taken", _} = changeset.errors[:name]
    end

    test "returns a changeset for invalid repository fields" do
      assert {:error, changeset} =
               Domains.create_domain(%{
                 name: "Hive",
                 github_repository_owner: "-tuist",
                 github_repository_name: "hive"
               })

      assert {"must be a valid GitHub owner", _} = changeset.errors[:github_repository_owner]
      assert Repo.aggregate(Domain, :count) == 0
    end
  end

  describe "list_domains/0" do
    test "returns domains ordered by name with their project preloaded" do
      assert {:ok, _} =
               Domains.create_domain(%{
                 name: "Forge",
                 github_repository_owner: "tuist",
                 github_repository_name: "forge"
               })

      assert {:ok, _} = Domains.create_domain(%{name: "Atlas"})

      assert [atlas, forge] = Domains.list_domains()
      assert atlas.name == "Atlas"
      assert forge.name == "Forge"
      assert [%GitHubRepository{name: "forge"}] = forge.project.github_repositories
      assert %Project{} = atlas.project
    end
  end

  describe "get_domain!/1" do
    test "returns a domain with its project's repositories preloaded" do
      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert domain = Domains.get_domain!(domain.id)

      assert [%GitHubRepository{owner: "tuist", name: "hive"}] =
               domain.project.github_repositories
    end
  end

  describe "delete_domain/1" do
    test "deletes the domain but leaves the project's repository intact" do
      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert {:ok, _domain} = Domains.delete_domain(domain)

      assert Repo.aggregate(Domain, :count) == 0
      assert Repo.aggregate(GitHubRepository, :count) == 1
    end
  end

  describe "update_domain/2" do
    test "updates domain fields" do
      assert {:ok, domain} = Domains.create_domain(%{name: "Atlas"})

      assert {:ok, domain} =
               Domains.update_domain(domain, %{
                 name: "Atlas Cloud",
                 description: "Internal domain planning.",
                 visibility: "private"
               })

      assert domain.name == "Atlas Cloud"
      assert domain.description == "Internal domain planning."
      assert domain.visibility == :private
    end

    test "replaces the project's repository when the form swaps it" do
      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert {:ok, domain} =
               Domains.update_domain(domain, %{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "tuist"
               })

      assert [%GitHubRepository{owner: "tuist"} | _] =
               domain.project.github_repositories
    end

    test "keeps repositories when repository fields are omitted" do
      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert {:ok, domain} =
               Domains.update_domain(domain, %{name: "Hive app", visibility: "private"})

      assert domain.name == "Hive app"
      assert domain.visibility == :private

      assert [%GitHubRepository{owner: "tuist", name: "hive"}] =
               domain.project.github_repositories
    end
  end
end
