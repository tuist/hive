defmodule Hive.Notifications.Subscription do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @topics [
    :forage_new_items,
    :forage_item_updates,
    :spec_new,
    :spec_updates,
    :domain_drops,
    :weekly_drop_digest
  ]
  @scope_types [:global, :domain, :forage_item, :spec]
  @cadences [:immediate, :daily]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_subscriptions" do
    field :topic, Ecto.Enum, values: @topics
    field :scope_type, Ecto.Enum, values: @scope_types
    field :scope_id, :string
    field :cadence, Ecto.Enum, values: @cadences, default: :immediate

    belongs_to :user, Hive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def topics, do: @topics
  def cadences, do: @cadences

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:user_id, :topic, :scope_type, :scope_id, :cadence])
    |> validate_required([:user_id, :topic, :scope_type, :scope_id, :cadence])
    |> validate_inclusion(:topic, @topics)
    |> validate_inclusion(:scope_type, @scope_types)
    |> validate_inclusion(:cadence, @cadences)
    |> validate_length(:scope_id, max: 255)
    |> validate_scope()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :topic, :scope_type, :scope_id],
      name: :notification_subscriptions_user_topic_scope_index
    )
    |> check_constraint(:topic, name: :notification_subscriptions_topic_check)
    |> check_constraint(:scope_type, name: :notification_subscriptions_scope_type_check)
    |> check_constraint(:cadence, name: :notification_subscriptions_cadence_check)
    |> check_constraint(:scope_type, name: :notification_subscriptions_scope_check)
  end

  defp validate_scope(changeset) do
    topic = get_field(changeset, :topic)
    scope_type = get_field(changeset, :scope_type)
    scope_id = get_field(changeset, :scope_id)

    expected =
      case topic do
        topic when topic in [:forage_new_items, :spec_new, :weekly_drop_digest] ->
          {:global, "global"}

        :forage_item_updates ->
          {:forage_item, scope_id}

        :spec_updates ->
          {:spec, scope_id}

        :domain_drops ->
          {:domain, scope_id}

        _other ->
          nil
      end

    if expected == {scope_type, scope_id} do
      changeset
    else
      add_error(changeset, :scope_type, "does not match the notification topic")
    end
  end
end
