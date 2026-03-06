defmodule Hive.Integrations.SlackIntegration do
  use Hive.Schema
  import Ecto.Changeset

  schema "slack_integrations" do
    field :name, :string
    field :bot_token, :string
    field :team_name, :string
    field :team_id, :string

    has_many :channels, Hive.Integrations.SlackChannel

    timestamps()
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:name, :bot_token, :team_name, :team_id])
    |> validate_required([:name, :bot_token])
  end
end
