defmodule Hive.Meadows do
  @moduledoc """
  Configures the meadows managed by this Hive instance.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Hive.Auth
  alias Hive.Meadows.GitHubRepository
  alias Hive.Meadows.Meadow
  alias Hive.Meadows.MeadowRepository
  alias Hive.Repo

  def list_meadows do
    Meadow
    |> order_by([meadow], asc: meadow.name)
    |> preload(:github_repositories)
    |> Repo.all()
  end

  @doc """
  Lists meadows the `user` is allowed to see. Members see every meadow;
  anyone else sees only those marked `:public`. Anonymous viewers (a `nil`
  user) get the same public-only view.
  """
  def list_visible_meadows(user) do
    query =
      Meadow
      |> order_by([meadow], asc: meadow.name)
      |> preload(:github_repositories)

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
    |> preload(:github_repositories)
    |> Repo.get!(id)
  end

  @doc """
  Returns `{:ok, meadow}` when `user` is allowed to see the meadow with
  `id`, or `{:error, :not_found}` for a missing record, a malformed id,
  or a private meadow viewed by a non-member.
  """
  def fetch_visible_meadow(id, user) do
    case Repo.get(Meadow, id) do
      nil ->
        {:error, :not_found}

      %Meadow{visibility: :private} = meadow ->
        if Auth.member?(user),
          do: {:ok, Repo.preload(meadow, :github_repositories)},
          else: {:error, :not_found}

      %Meadow{} = meadow ->
        {:ok, Repo.preload(meadow, :github_repositories)}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_meadow(meadow \\ %Meadow{}, attrs \\ %{}) do
    Meadow.changeset(meadow, attrs)
  end

  def create_meadow(attrs) do
    changeset = change_meadow(%Meadow{}, attrs)

    if changeset.valid? do
      changeset
      |> create_meadow_multi(Meadow.repository_attrs(changeset))
      |> Repo.transaction()
      |> case do
        {:ok, %{meadow: meadow}} ->
          {:ok, Repo.preload(meadow, :github_repositories)}

        {:error, :meadow, changeset, _changes} ->
          {:error, changeset}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  def delete_meadow(%Meadow{} = meadow), do: Repo.delete(meadow)

  def update_meadow(%Meadow{} = meadow, attrs) do
    meadow = Repo.preload(meadow, :github_repositories)
    changeset = change_meadow(meadow, attrs)
    repository_fields_present? = repository_fields_present?(attrs)
    repository_attrs = Meadow.repository_attrs(changeset)

    if changeset.valid? do
      changeset
      |> update_meadow_multi(meadow, repository_attrs, repository_fields_present?)
      |> Repo.transaction()
      |> case do
        {:ok, %{meadow: meadow}} ->
          {:ok, Repo.preload(meadow, :github_repositories, force: true)}

        {:error, :meadow, changeset, _changes} ->
          {:error, changeset}

        {:error, _step, changeset, _changes} ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp create_meadow_multi(meadow_changeset, nil) do
    Multi.insert(Multi.new(), :meadow, meadow_changeset)
  end

  defp create_meadow_multi(meadow_changeset, repository_attrs) do
    Multi.new()
    |> Multi.insert(:meadow, meadow_changeset)
    |> Multi.run(:github_repository, fn repo, _changes ->
      get_or_create_github_repository(repo, repository_attrs)
    end)
    |> Multi.insert(:meadow_repository, fn %{meadow: meadow, github_repository: repository} ->
      MeadowRepository.changeset(%MeadowRepository{}, %{
        meadow_id: meadow.id,
        github_repository_id: repository.id
      })
    end)
  end

  defp update_meadow_multi(
         meadow_changeset,
         meadow,
         repository_attrs,
         repository_fields_present?
       ) do
    Multi.new()
    |> Multi.update(:meadow, meadow_changeset)
    |> maybe_replace_meadow_repository(meadow, repository_attrs, repository_fields_present?)
  end

  defp maybe_replace_meadow_repository(multi, _meadow, _repository_attrs, false), do: multi

  defp maybe_replace_meadow_repository(multi, meadow, nil, true) do
    Multi.delete_all(multi, :meadow_repositories, meadow_repositories_query(meadow.id))
  end

  defp maybe_replace_meadow_repository(multi, meadow, repository_attrs, true) do
    multi
    |> Multi.run(:github_repository, fn repo, _changes ->
      get_or_create_github_repository(repo, repository_attrs)
    end)
    |> Multi.delete_all(:meadow_repositories, meadow_repositories_query(meadow.id))
    |> Multi.insert(:meadow_repository, fn %{meadow: meadow, github_repository: repository} ->
      MeadowRepository.changeset(%MeadowRepository{}, %{
        meadow_id: meadow.id,
        github_repository_id: repository.id
      })
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

  defp meadow_repositories_query(meadow_id) do
    from(meadow_repository in MeadowRepository,
      where: meadow_repository.meadow_id == ^meadow_id
    )
  end

  defp repository_fields_present?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, "github_repository_owner") or
      Map.has_key?(attrs, :github_repository_owner) or
      Map.has_key?(attrs, "github_repository_name") or
      Map.has_key?(attrs, :github_repository_name)
  end

  defp repository_fields_present?(_attrs), do: false
end
