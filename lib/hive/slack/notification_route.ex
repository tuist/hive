defmodule Hive.Slack.NotificationRoute do
  @moduledoc """
  Routes a Hive object type to the Slack channel that should receive its
  notifications for one installed workspace.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Slack.Installation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "slack_notification_routes" do
    field :object_type, :string
    field :slack_channel_id, :string
    field :notification_events, {:array, :string}, default: []

    belongs_to :installation, Installation

    timestamps(type: :utc_datetime)
  end

  def changeset(route, attrs, allowed_object_types, allowed_events) do
    route
    |> cast(attrs, [:installation_id, :object_type, :slack_channel_id, :notification_events])
    |> update_change(:slack_channel_id, &normalize_string/1)
    |> update_change(:notification_events, &normalize_events/1)
    |> validate_required([:installation_id, :object_type, :slack_channel_id])
    |> validate_inclusion(:object_type, allowed_object_types)
    |> validate_length(:slack_channel_id, max: 80)
    |> validate_subset(:notification_events, allowed_events)
    |> unique_constraint([:installation_id, :object_type])
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
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
