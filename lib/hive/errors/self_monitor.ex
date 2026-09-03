defmodule Hive.Errors.SelfMonitor do
  @moduledoc """
  Bootstraps the "Hive" self-project so Hive's own crashes can be
  recorded through the same pipeline external SDKs use, and registers
  the Erlang logger handler that captures them.

  The bootstrap is idempotent: if the project or its default key
  already exists it reuses them. Runs after the app supervision tree
  has started so the Postgres repo is available.
  """

  require Logger

  alias Hive.Errors
  alias Hive.Errors.LoggerHandler
  alias Hive.Errors.ProjectKey
  alias Hive.Projects
  alias Hive.Projects.Project
  alias Hive.Repo

  @project_name "Hive"

  @doc """
  Provisions the self-project and default DSN (if missing) and installs
  the logger handler. Safe to call at boot; returns `:ok` even when
  ClickHouse is disabled — the handler simply becomes a no-op.
  """
  def install do
    with true <- Errors.enabled?(),
         {:ok, project} <- ensure_project(),
         {:ok, _key} <- ensure_default_key(project) do
      Application.put_env(:hive, :errors_self_project_id, project.id)
      LoggerHandler.attach()
      :ok
    else
      false ->
        :ok

      error ->
        Logger.warning("errors.self_monitor: bootstrap failed: #{inspect(error)}")
        :ok
    end
  rescue
    error ->
      Logger.warning("errors.self_monitor: bootstrap crashed: #{Exception.message(error)}")
      :ok
  end

  @doc """
  Returns the id of the "Hive" self-project once bootstrap has
  completed, or `nil` when it has not (ClickHouse disabled, boot
  failure, or bootstrap hasn't run yet).
  """
  def self_project_id, do: Application.get_env(:hive, :errors_self_project_id)

  defp ensure_project do
    case Repo.get_by(Project, name: @project_name) do
      %Project{} = project ->
        {:ok, project}

      nil ->
        Projects.create_project(%{
          "name" => @project_name,
          "description" => "Errors captured from the running Hive instance.",
          "visibility" => "private"
        })
    end
  end

  defp ensure_default_key(project) do
    case Errors.list_project_keys(project.id) do
      [%ProjectKey{} = key | _] -> {:ok, key}
      [] -> Errors.create_project_key(project.id, %{"name" => "self"})
    end
  end
end
