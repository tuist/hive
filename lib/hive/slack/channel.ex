defmodule Hive.Slack.Channel do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Slack.Installation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "slack_channels" do
    field :slack_channel_id, :string
    field :name, :string
    field :is_private, :boolean, default: false
    field :is_archived, :boolean, default: false
    field :topic, :string
    field :purpose, :string
    field :last_synced_at, :utc_datetime

    belongs_to :installation, Installation

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :installation_id,
      :slack_channel_id,
      :name,
      :is_private,
      :is_archived,
      :topic,
      :purpose,
      :last_synced_at
    ])
    |> validate_required([:installation_id, :slack_channel_id])
    |> unique_constraint([:installation_id, :slack_channel_id])
  end
end
