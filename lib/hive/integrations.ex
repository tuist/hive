defmodule Hive.Integrations do
  alias Hive.Repo
  alias Hive.Integrations.SlackIntegration
  alias Hive.Integrations.SlackChannel

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
end
