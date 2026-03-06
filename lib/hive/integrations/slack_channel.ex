defmodule Hive.Integrations.SlackChannel do
  use Hive.Schema
  import Ecto.Changeset

  schema "slack_channels" do
    field :channel_id, :string
    field :channel_name, :string

    belongs_to :slack_integration, Hive.Integrations.SlackIntegration

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:channel_id, :channel_name, :slack_integration_id])
    |> validate_required([:channel_id, :channel_name, :slack_integration_id])
    |> unique_constraint([:channel_id, :slack_integration_id])
  end
end
