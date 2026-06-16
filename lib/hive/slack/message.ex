defmodule Hive.Slack.Message do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Slack.Channel
  alias Hive.Slack.Installation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "slack_messages" do
    field :slack_user_id, :string
    field :slack_ts, :string
    field :thread_ts, :string
    field :text, :string
    field :raw_payload, :map

    belongs_to :installation, Installation
    belongs_to :channel, Channel

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :installation_id,
      :channel_id,
      :slack_user_id,
      :slack_ts,
      :thread_ts,
      :text,
      :raw_payload
    ])
    |> validate_required([:installation_id, :channel_id, :slack_ts])
    |> unique_constraint([:channel_id, :slack_ts])
  end
end
