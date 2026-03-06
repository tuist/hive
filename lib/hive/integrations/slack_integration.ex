defmodule Hive.Integrations.SlackIntegration do
  use Hive.Schema
  import Ecto.Changeset

  schema "slack_integrations" do
    field :name, :string
    field :bot_token, :string
    field :signing_secret, :string

    has_many :channels, Hive.Integrations.SlackChannel

    timestamps()
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [:name, :bot_token, :signing_secret])
    |> validate_required([:name, :bot_token])
  end
end
