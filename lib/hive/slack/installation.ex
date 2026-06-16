defmodule Hive.Slack.Installation do
  @moduledoc """
  One row per Slack workspace that has installed Hive's Slack app.

  The Slack signing secret is app-wide and lives in config; the bot token
  is per-workspace and is captured here from the OAuth code exchange.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.User
  alias Hive.Slack.Channel
  alias Hive.Slack.Message
  alias Hive.Slack.User, as: SlackUser

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "slack_installations" do
    field :team_id, :string
    field :team_name, :string
    field :bot_user_id, :string
    field :bot_token, :string
    field :scope, :string
    field :installed_at, :utc_datetime
    field :disconnected_at, :utc_datetime

    belongs_to :installed_by_user, User
    has_many :channels, Channel
    has_many :users, SlackUser
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [
      :team_id,
      :team_name,
      :bot_user_id,
      :bot_token,
      :scope,
      :installed_at,
      :disconnected_at,
      :installed_by_user_id
    ])
    |> validate_required([:team_id])
    |> unique_constraint(:team_id)
  end

  def disconnect_changeset(installation) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    installation
    |> change(%{bot_token: nil, disconnected_at: now})
  end

  def connected?(%__MODULE__{bot_token: token, disconnected_at: nil})
      when is_binary(token) and token != "",
      do: true

  def connected?(_installation), do: false
end
