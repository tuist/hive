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
  alias Hive.Slack.NotificationRoute
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
    field :notification_channel_id, :string
    field :notification_events, {:array, :string}, default: []

    belongs_to :installed_by_user, User
    has_many :channels, Channel
    has_many :users, SlackUser
    has_many :messages, Message
    has_many :notification_routes, NotificationRoute

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
      :notification_channel_id,
      :notification_events,
      :installed_by_user_id
    ])
    |> validate_required([:team_id])
    |> unique_constraint(:team_id)
  end

  def notification_changeset(installation, attrs, allowed_events) do
    installation
    |> cast(attrs, [:notification_channel_id, :notification_events])
    |> update_change(:notification_channel_id, &normalize_string/1)
    |> update_change(:notification_events, &normalize_events/1)
    |> validate_length(:notification_channel_id, max: 80)
    |> validate_subset(:notification_events, allowed_events)
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

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_string(value), do: value

  defp normalize_events(events) when is_list(events) do
    events
    |> Enum.map(fn
      event when is_binary(event) -> String.trim(event)
      event -> event
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp normalize_events(_events), do: []
end
