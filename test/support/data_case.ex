defmodule Hive.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Hive.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Hive.DataCase
    end
  end

  setup tags do
    Hive.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Hive.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  def github_repository_for_domain!(domain) do
    domain.projects
    |> Enum.flat_map(&project_repositories/1)
    |> List.first()
  end

  def github_repositories_for_domain(domain) do
    domain.projects
    |> Enum.flat_map(&project_repositories/1)
  end

  defp project_repositories(%{github_repositories: repositories}) when is_list(repositories),
    do: repositories

  defp project_repositories(_project), do: []
end
