defmodule Hive.Notifications.Delivery do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Notifications.Event

  @statuses [:pending, :sent, :skipped, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_deliveries" do
    field :topic, Ecto.Enum, values: Hive.Notifications.Subscription.topics()
    field :cadence, Ecto.Enum, values: Hive.Notifications.Subscription.cadences()
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :scheduled_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :provider_message_id, :string
    field :skip_reason, :string
    field :last_error, :string

    belongs_to :event, Event
    belongs_to :user, Hive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :event_id,
      :user_id,
      :topic,
      :cadence,
      :status,
      :scheduled_at,
      :sent_at,
      :provider_message_id,
      :skip_reason,
      :last_error
    ])
    |> validate_required([:event_id, :user_id, :topic, :cadence, :status, :scheduled_at])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:provider_message_id, max: 500)
    |> validate_length(:skip_reason, max: 500)
    |> validate_length(:last_error, max: 1_000)
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:event_id, :user_id, :topic])
    |> check_constraint(:status, name: :notification_deliveries_status_check)
  end
end
