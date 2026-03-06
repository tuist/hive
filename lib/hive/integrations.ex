defmodule Hive.Integrations do
  alias Hive.Repo
  alias Hive.Integrations.SlackIntegration
  alias Hive.Integrations.SlackChannel
  alias Hive.Integrations.GitHubApp
  alias Hive.Integrations.GitHubRepository

  import Ecto.Query

  def list_slack_integrations do
    SlackIntegration
    |> order_by([i], asc: i.name)
    |> Repo.all()
    |> Repo.preload(:channels)
  end

  def get_slack_integration(id) do
    SlackIntegration
    |> Repo.get(id)
    |> Repo.preload(:channels)
  end

  def create_slack_integration(attrs) do
    %SlackIntegration{}
    |> SlackIntegration.changeset(attrs)
    |> Repo.insert()
  end

  def update_slack_integration(%SlackIntegration{} = integration, attrs) do
    integration
    |> SlackIntegration.changeset(attrs)
    |> Repo.update()
  end

  def delete_slack_integration(%SlackIntegration{} = integration) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(
      :channels,
      from(c in SlackChannel, where: c.slack_integration_id == ^integration.id)
    )
    |> Ecto.Multi.delete(:integration, integration)
    |> Repo.transaction()
    |> case do
      {:ok, %{integration: integration}} -> {:ok, integration}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def change_slack_integration(%SlackIntegration{} = integration, attrs \\ %{}) do
    SlackIntegration.changeset(integration, attrs)
  end

  def add_slack_channel(%SlackIntegration{} = integration, attrs) do
    attrs = Map.put(attrs, :slack_integration_id, integration.id)

    %SlackChannel{}
    |> SlackChannel.changeset(Map.new(attrs))
    |> Repo.insert()
  end

  def delete_slack_channel(id) do
    case Repo.get(SlackChannel, id) do
      nil -> {:error, :not_found}
      channel -> Repo.delete(channel)
    end
  end

  def list_slack_channels(%SlackIntegration{} = integration) do
    SlackChannel
    |> where([c], c.slack_integration_id == ^integration.id)
    |> order_by([c], asc: c.channel_name)
    |> Repo.all()
  end

  def find_monitored_channel(channel_id) do
    SlackChannel
    |> where([c], c.channel_id == ^channel_id)
    |> Repo.one()
    |> Repo.preload(:slack_integration)
  end

  def list_all_slack_integrations_with_signing_secret do
    SlackIntegration
    |> where([i], not is_nil(i.signing_secret))
    |> Repo.all()
  end

  # GitHub Apps

  def list_github_apps do
    GitHubApp
    |> order_by([a], asc: a.name)
    |> Repo.all()
    |> Repo.preload(:repositories)
  end

  def get_github_app(id) do
    GitHubApp
    |> Repo.get(id)
    |> Repo.preload(:repositories)
  end

  def create_github_app(attrs) do
    %GitHubApp{}
    |> GitHubApp.changeset(attrs)
    |> Repo.insert()
  end

  def update_github_app(%GitHubApp{} = app, attrs) do
    app
    |> GitHubApp.changeset(attrs)
    |> Repo.update()
  end

  def delete_github_app(%GitHubApp{} = app) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(
      :repositories,
      from(r in GitHubRepository, where: r.github_app_id == ^app.id)
    )
    |> Ecto.Multi.delete(:app, app)
    |> Repo.transaction()
    |> case do
      {:ok, %{app: app}} -> {:ok, app}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def change_github_app(%GitHubApp{} = app, attrs \\ %{}) do
    GitHubApp.changeset(app, attrs)
  end

  def add_github_repository(%GitHubApp{} = app, attrs) do
    attrs = Map.put(attrs, :github_app_id, app.id)

    %GitHubRepository{}
    |> GitHubRepository.changeset(Map.new(attrs))
    |> Repo.insert()
  end

  def delete_github_repository(id) do
    case Repo.get(GitHubRepository, id) do
      nil -> {:error, :not_found}
      repository -> Repo.delete(repository)
    end
  end

  def list_github_repositories(%GitHubApp{} = app) do
    GitHubRepository
    |> where([r], r.github_app_id == ^app.id)
    |> order_by([r], asc: r.owner, asc: r.repo)
    |> Repo.all()
  end

  def find_monitored_repository(owner, repo) do
    GitHubRepository
    |> where([r], r.owner == ^owner and r.repo == ^repo)
    |> Repo.one()
    |> Repo.preload(:github_app)
  end
end
