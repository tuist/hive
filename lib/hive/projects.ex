defmodule Hive.Projects do
  @moduledoc """
  Projects are the top-level groupings tracked by a Hive instance: a
  product, codebase, or service. Each project owns its connected GitHub
  repositories and the RSS sources whose entries feed associated
  domains.

  For instances that only care about one product (the "Kura case"),
  the operator can create a single project with zero domains and the
  rest of the dashboard treats every drop as belonging to that project.
  """

  import Ecto.Query

  alias Hive.Auth
  alias Hive.Forage.Grafana
  alias Hive.Domains.GitHubRepository
  alias Hive.Domains.Domain
  alias Hive.Projects.Project
  alias Hive.Projects.ProjectDomain
  alias Hive.Projects.Webhook
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

  def change_repository_for_project(%Project{id: project_id}, attrs \\ %{}) do
    %GitHubRepository{project_id: project_id}
    |> GitHubRepository.changeset(put_project_id(attrs, project_id))
  end

  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def create_repository_for_project(%Project{id: project_id}, attrs) do
    %GitHubRepository{}
    |> GitHubRepository.changeset(put_project_id(attrs, project_id))
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  def delete_repository_from_project(%Project{id: project_id}, repository_id)
      when is_binary(repository_id) do
    case Repo.get_by(GitHubRepository, id: repository_id, project_id: project_id) do
      %GitHubRepository{} = repository -> Repo.delete(repository)
      nil -> {:error, :not_found}
    end
  end

  def unlink_domain_from_project(%Project{id: project_id}, domain_id) when is_binary(domain_id) do
    ProjectDomain
    |> where([link], link.project_id == ^project_id and link.domain_id == ^domain_id)
    |> Repo.delete_all()

    :ok
  end

  def link_domain_to_project(%Project{id: project_id}, domain_id) when is_binary(domain_id) do
    case Repo.get(Domain, domain_id) do
      %Domain{} = domain ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.insert_all(
          ProjectDomain,
          [
            %{
              domain_id: domain.id,
              project_id: project_id,
              inserted_at: now,
              updated_at: now
            }
          ],
          on_conflict: :nothing,
          conflict_target: [:project_id, :domain_id]
        )

        {:ok, domain}

      nil ->
        {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def link_domain_to_project(_project, _domain_id), do: {:error, :not_found}

  def list_domains_available_for_project(%Project{id: project_id}) do
    linked_domain_ids =
      ProjectDomain
      |> where([link], link.project_id == ^project_id)
      |> select([link], link.domain_id)

    Domain
    |> where([domain], domain.id not in subquery(linked_domain_ids))
    |> order_by([domain], asc: domain.name)
    |> Repo.all()
  end

  @doc """
  Lists domains belonging to the given project. Useful as the candidate
  set for `Hive.Drops.DomainClassification`.
  """
  def list_domains_for_project(project_id) when is_binary(project_id) do
    Domain
    |> join(:inner, [domain], link in ProjectDomain,
      on: link.domain_id == domain.id and link.project_id == ^project_id
    )
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

  def list_linked_repository_full_names do
    GitHubRepository
    |> select([repo], {repo.owner, repo.name})
    |> Repo.all()
    |> MapSet.new()
  end

  def ingest_webhook(:grafana, %Project{} = project, %Webhook{} = webhook, payload) do
    with {:ok, alerts} <- Grafana.ingest(project, webhook, payload) do
      Hive.Domains.schedule_evolution()
      {:ok, alerts}
    end
  end

  defp preload(project),
    do: Repo.preload(project, [:domains, :github_repositories, :webhooks])

  defp put_project_id(attrs, project_id) when is_map(attrs) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, "project_id", project_id)
    else
      Map.put(attrs, :project_id, project_id)
    end
  end
end
