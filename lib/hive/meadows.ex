defmodule Hive.Meadows do
  @moduledoc """
  Configures the meadows managed by this Hive instance. Meadows are
  sub-domains *within* a project; repositories belong to the project,
  not directly to a meadow.

  For backward compatibility with the single-form UX, `create_meadow/1`
  and `update_meadow/2` still accept the virtual `github_repository_*`
  fields and `name`/`visibility`; when no `project_id` is supplied,
  they bootstrap a project named after the meadow and attach the repo
  there.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Hive.Auth
  alias Hive.Forage.Grafana
  alias Hive.Meadows.GitHubRepository
  alias Hive.Meadows.Meadow
  alias Hive.Meadows.Webhook
  alias Hive.Projects.Project
  alias Hive.Repo

  defdelegate evolve_from_work_items(opts \\ []), to: Hive.Meadows.Evolution
  defdelegate schedule_evolution, to: Hive.Meadows.EvolutionWorker, as: :enqueue

  def ingest_webhook(:grafana, %Meadow{} = meadow, %Webhook{} = webhook, payload) do
    with {:ok, alerts} <- Grafana.ingest(meadow, webhook, payload) do
      schedule_evolution()
      {:ok, alerts}
    end
  end

  def list_meadows do
    Meadow
    |> order_by([meadow], asc: meadow.name)
    |> preload(project: :github_repositories)
    |> Repo.all()
  end

  @doc """
  Lists meadows the `user` is allowed to see. Members see every meadow;
  anyone else sees only those marked `:public`.
  """
  def list_visible_meadows(user) do
    query =
      Meadow
      |> order_by([meadow], asc: meadow.name)
      |> preload(project: :github_repositories)

    if Auth.member?(user) do
      Repo.all(query)
    else
      query
      |> where([meadow], meadow.visibility == :public)
      |> Repo.all()
    end
  end

  def get_meadow!(id) do
    Meadow
    |> preload(project: :github_repositories)
    |> Repo.get!(id)
  end

  def fetch_visible_meadow(id, user) do
    case Repo.get(Meadow, id) do
      nil ->
        {:error, :not_found}

      %Meadow{visibility: :private} = meadow ->
        if Auth.member?(user),
          do: {:ok, preload_full(meadow)},
          else: {:error, :not_found}

      %Meadow{} = meadow ->
        {:ok, preload_full(meadow)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_meadow(meadow \\ %Meadow{}, attrs \\ %{}) do
    Meadow.changeset(meadow, attrs)
  end

  def create_meadow(attrs) do
    changeset = change_meadow(%Meadow{}, attrs)
    repository_attrs = Meadow.repository_attrs(changeset)

    if changeset.valid? do
      Multi.new()
      |> ensure_project_multi(changeset)
      |> Multi.insert(:meadow, fn %{project: project} ->
        Ecto.Changeset.put_change(changeset, :project_id, project.id)
      end)
      |> upsert_repository_multi(repository_attrs)
      |> Repo.transaction()
      |> case do
        {:ok, %{meadow: meadow}} ->
          {:ok, preload_full(meadow)}

        {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  def delete_meadow(%Meadow{} = meadow), do: Repo.delete(meadow)

  def update_meadow(%Meadow{} = meadow, attrs) do
    meadow = preload_full(meadow)
    changeset = change_meadow(meadow, attrs)
    repository_fields_present? = repository_fields_present?(attrs)
    repository_attrs = Meadow.repository_attrs(changeset)

    if changeset.valid? do
      Multi.new()
      |> Multi.update(:meadow, changeset)
      |> maybe_replace_repository(meadow, repository_attrs, repository_fields_present?)
      |> Repo.transaction()
      |> case do
        {:ok, %{meadow: meadow}} ->
          {:ok, preload_full(meadow)}

        {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp ensure_project_multi(multi, changeset) do
    case Ecto.Changeset.get_field(changeset, :project_id) do
      nil ->
        attrs = bootstrap_project_attrs(changeset)
        Multi.run(multi, :project, fn repo, _changes -> bootstrap_project(repo, attrs) end)

      project_id when is_binary(project_id) ->
        Multi.run(multi, :project, fn repo, _changes -> fetch_project(repo, project_id) end)
    end
  end

  defp bootstrap_project_attrs(changeset) do
    %{
      name: Ecto.Changeset.get_field(changeset, :name),
      description: Ecto.Changeset.get_field(changeset, :description),
      visibility: Ecto.Changeset.get_field(changeset, :visibility) || :public
    }
  end

  defp bootstrap_project(repo, %{name: name} = attrs) do
    case repo.get_by(Project, name: name) do
      %Project{} = project -> {:ok, project}
      nil -> %Project{} |> Project.changeset(attrs) |> repo.insert()
    end
  end

  defp fetch_project(repo, project_id) do
    case repo.get(Project, project_id) do
      %Project{} = project -> {:ok, project}
      nil -> {:error, :project_not_found}
    end
  end

  defp upsert_repository_multi(multi, nil), do: multi

  defp upsert_repository_multi(multi, repository_attrs) do
    Multi.run(multi, :github_repository, fn repo, %{project: project} ->
      attrs = Map.put(repository_attrs, :project_id, project.id)
      get_or_create_github_repository(repo, attrs)
    end)
  end

  defp maybe_replace_repository(multi, _meadow, _repository_attrs, false), do: multi

  defp maybe_replace_repository(multi, _meadow, nil, true), do: multi

  defp maybe_replace_repository(multi, meadow, repository_attrs, true) do
    Multi.run(multi, :github_repository, fn repo, _changes ->
      attrs = Map.put(repository_attrs, :project_id, meadow.project_id)
      get_or_create_github_repository(repo, attrs)
    end)
  end

  defp get_or_create_github_repository(repo, attrs) do
    case repo.get_by(GitHubRepository, owner: attrs.owner, name: attrs.name) do
      %GitHubRepository{} = repository ->
        repository
        |> GitHubRepository.changeset(attrs)
        |> repo.update()

      nil ->
        %GitHubRepository{}
        |> GitHubRepository.changeset(attrs)
        |> repo.insert()
    end
  end

  defp repository_fields_present?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, "github_repository_owner") or
      Map.has_key?(attrs, :github_repository_owner) or
      Map.has_key?(attrs, "github_repository_name") or
      Map.has_key?(attrs, :github_repository_name)
  end

  defp repository_fields_present?(_attrs), do: false

  defp preload_full(meadow),
    do: Repo.preload(meadow, [project: :github_repositories], force: true)
end
