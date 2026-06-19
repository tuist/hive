defmodule Hive.Projects do
  @moduledoc """
  Projects are the top-level groupings tracked by a Hive instance: a
  product, codebase, or service. Each project owns its domains
  (sub-domains), its connected GitHub repositories, and the RSS sources
  whose entries feed those domains.

  For instances that only care about one product (the "Kura case"),
  the operator can create a single project with zero domains and the
  rest of the dashboard treats every drop as belonging to that project.
  """

  import Ecto.Query

  alias Hive.Auth
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
  alias Hive.Projects.Project
  alias Hive.Repo

  def list_projects do
    Project
    |> order_by([project], asc: project.name)
    |> Repo.all()
  end

  def list_visible_projects(user) do
    if Auth.member?(user) do
      list_projects()
    else
      Project
      |> where([project], project.visibility == :public)
      |> order_by([project], asc: project.name)
      |> Repo.all()
    end
  end

  def get_project!(id) do
    Project
    |> Repo.get!(id)
    |> Repo.preload([:domains, :github_repositories])
  end

  def fetch_visible_project(id, user) do
    case Repo.get(Project, id) do
      nil ->
        {:error, :not_found}

      %Project{visibility: :private} = project ->
        if Auth.member?(user),
          do: {:ok, preload(project)},
          else: {:error, :not_found}

      %Project{} = project ->
        {:ok, preload(project)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_project(project \\ %Project{}, attrs \\ %{}),
    do: Project.changeset(project, attrs)

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  @doc """
  Lists domains belonging to the given project. Useful as the candidate
  set for `Hive.Drops.DomainClassification`.
  """
  def list_domains_for_project(project_id) when is_binary(project_id) do
    Domain
    |> where([domain], domain.project_id == ^project_id)
    |> order_by([domain], asc: domain.name)
    |> Repo.all()
  end

  @doc """
  Lists GitHub repositories belonging to the given project.
  """
  def list_repositories_for_project(project_id) when is_binary(project_id) do
    GitHubRepository
    |> where([repo], repo.project_id == ^project_id)
    |> order_by([repo], asc: repo.owner, asc: repo.name)
    |> Repo.all()
  end

  defp preload(project),
    do: Repo.preload(project, [:domains, :github_repositories])
end
