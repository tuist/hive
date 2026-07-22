defmodule Hive.Notifications.Event do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @types [
    :forage_item_created,
    :forage_item_updated,
    :forage_comment_created,
    :forage_spec_created,
    :forage_flight_completed,
    :spec_created,
    :spec_updated,
    :spec_comment_created,
    :spec_review_requested,
    :drop_published,
    :weekly_drop_digest_published
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_events" do
    field :deduplication_key, :string
    field :type, Ecto.Enum, values: @types
    field :resource_type, :string
    field :resource_id, :string
    field :data, :map, default: %{}
    field :occurred_at, :utc_datetime
    field :dispatched_at, :utc_datetime

    belongs_to :actor, Hive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def types, do: @types

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :deduplication_key,
      :type,
      :resource_type,
      :resource_id,
      :actor_id,
      :data,
      :occurred_at,
      :dispatched_at
    ])
    |> put_default_occurred_at()
    |> validate_required([
      :deduplication_key,
      :type,
      :resource_type,
      :resource_id,
      :occurred_at
    ])
    |> validate_inclusion(:type, @types)
    |> validate_length(:deduplication_key, max: 500)
    |> validate_length(:resource_type, max: 80)
    |> validate_length(:resource_id, max: 255)
    |> foreign_key_constraint(:actor_id)
    |> unique_constraint(:deduplication_key)
    |> check_constraint(:type, name: :notification_events_type_check)
  end

  defp put_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _datetime -> changeset
    end
  end
end
