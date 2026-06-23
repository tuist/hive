defmodule Hive.DomainsTest do
  use Hive.DataCase, async: true

  alias Hive.Domains
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
  alias Hive.Projects
  alias Hive.Projects.Project

  describe "change_domain/2" do
    test "is valid with a name" do
      changeset =
        Domains.change_domain(%Domain{}, %{name: "Hive"})

      assert changeset.valid?
      assert get_field(changeset, :visibility) == :public
    end

    test "requires a name" do
      changeset = Domains.change_domain(%Domain{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
    end

    test "rejects unknown visibility" do
      changeset =
        Domains.change_domain(%Domain{}, %{
          name: "Hive",
          project_id: Ecto.UUID.generate(),
          visibility: "internal"
        })

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:visibility]
    end

    test "requires repository owner and name together" do
      owner_changeset =
        Domains.change_domain(%Domain{}, %{
          name: "Hive",
          project_id: Ecto.UUID.generate(),
          github_repository_owner: "tuist"
        })

      name_changeset =
        Domains.change_domain(%Domain{}, %{
          name: "Hive",
          project_id: Ecto.UUID.generate(),
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
          project_id: Ecto.UUID.generate(),
          github_repository_owner: " Tuist ",
          github_repository_name: " Hive "
        })

      assert get_change(changeset, :github_repository_owner) == "tuist"
      assert get_change(changeset, :github_repository_name) == "hive"
    end
  end

  describe "create_domain/1" do
    test "can create a domain without a project association" do
      assert {:ok, domain} = Domains.create_domain(%{name: "Hive"})

      assert domain.name == "Hive"
      assert domain.projects == []
    end

    test "creates a private domain associated with a private project" do
      project = create_project!(%{name: "Atlas", visibility: "private"})

      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Atlas Operations",
                 project_id: project.id,
                 visibility: "private"
               })

      assert domain.visibility == :private
      assert [%Project{visibility: :private}] = domain.projects
    end

    test "attaches a GitHub repository to the selected project" do
      project = create_project!(%{name: "Hive"})

      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 project_id: project.id,
                 description: "Domain orchestration",
                 github_repository_owner: "Tuist",
                 github_repository_name: "Hive"
               })

      assert domain.description == "Domain orchestration"

      assert [%GitHubRepository{owner: "tuist", name: "hive"}] =
               project_repositories(domain)

      assert Repo.aggregate(GitHubRepository, :count) == 1
    end

    test "links a domain to an existing project when project_id is supplied" do
      project = create_project!(%{name: "Tuist", visibility: "public"})

      assert {:ok, cache} =
               Domains.create_domain(%{name: "Cache", project_id: project.id})

      assert {:ok, generated} =
               Domains.create_domain(%{name: "Generated", project_id: project.id})

      assert [%Project{id: cache_project_id}] = cache.projects
      assert [%Project{id: generated_project_id}] = generated.projects
      assert cache_project_id == project.id
      assert generated_project_id == project.id
    end

    test "rejects duplicate domain names" do
      project = create_project!(%{name: "Hive"})

      assert {:ok, _} = Domains.create_domain(%{name: "Hive", project_id: project.id})

      assert {:error, changeset} = Domains.create_domain(%{name: "Hive", project_id: project.id})

      assert {"has already been taken", _} = changeset.errors[:name]
    end

    test "returns a changeset for invalid repository fields" do
      project = create_project!(%{name: "Hive"})

      assert {:error, changeset} =
               Domains.create_domain(%{
                 name: "Hive",
                 project_id: project.id,
                 github_repository_owner: "-tuist",
                 github_repository_name: "hive"
               })

      assert {"must be a valid GitHub owner", _} = changeset.errors[:github_repository_owner]
      assert Repo.aggregate(Domain, :count) == 0
    end
  end

  describe "list_domains/0" do
    test "returns domains ordered by name with their projects preloaded" do
      forge_project = create_project!(%{name: "Forge"})
      atlas_project = create_project!(%{name: "Atlas"})

      assert {:ok, _} =
               Domains.create_domain(%{
                 name: "Forge",
                 project_id: forge_project.id,
                 github_repository_owner: "tuist",
                 github_repository_name: "forge"
               })

      assert {:ok, _} = Domains.create_domain(%{name: "Atlas", project_id: atlas_project.id})

      assert [atlas, forge] = Domains.list_domains()
      assert atlas.name == "Atlas"
      assert forge.name == "Forge"
      assert [%GitHubRepository{name: "forge"}] = project_repositories(forge)
      assert [%Project{}] = atlas.projects
    end
  end

  describe "get_domain!/1" do
    test "returns a domain with its projects' repositories preloaded" do
      project = create_project!(%{name: "Hive"})

      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 project_id: project.id,
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert domain = Domains.get_domain!(domain.id)

      assert [%GitHubRepository{owner: "tuist", name: "hive"}] =
               project_repositories(domain)
    end
  end

  describe "delete_domain/1" do
    test "deletes the domain but leaves the project's repository intact" do
      project = create_project!(%{name: "Hive"})

      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 project_id: project.id,
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
      project = create_project!(%{name: "Atlas"})

      assert {:ok, domain} = Domains.create_domain(%{name: "Atlas", project_id: project.id})

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
      project = create_project!(%{name: "Hive"})

      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 project_id: project.id,
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
               project_repositories(domain)
    end

    test "keeps repositories when repository fields are omitted" do
      project = create_project!(%{name: "Hive"})

      assert {:ok, domain} =
               Domains.create_domain(%{
                 name: "Hive",
                 project_id: project.id,
                 github_repository_owner: "tuist",
                 github_repository_name: "hive"
               })

      assert {:ok, domain} =
               Domains.update_domain(domain, %{name: "Hive app", visibility: "private"})

      assert domain.name == "Hive app"
      assert domain.visibility == :private

      assert [%GitHubRepository{owner: "tuist", name: "hive"}] =
               project_repositories(domain)
    end
  end

  defp create_project!(attrs) do
    attrs = Map.put_new(attrs, :visibility, "public")
    {:ok, project} = Projects.create_project(attrs)
    project
  end

  defp project_repositories(%Domain{} = domain) do
    domain.projects
    |> Enum.flat_map(& &1.github_repositories)
    |> Enum.sort_by(&{&1.owner, &1.name})
  end
end
