defmodule Hive.Slack.User do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.User, as: HiveUser
  alias Hive.Slack.Installation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "slack_users" do
    field :slack_user_id, :string
    field :email, :string
    field :name, :string
    field :real_name, :string
    field :is_bot, :boolean, default: false
    field :deleted, :boolean, default: false

    belongs_to :installation, Installation
    belongs_to :linked_user, HiveUser

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :installation_id,
      :slack_user_id,
      :email,
      :name,
      :real_name,
      :is_bot,
      :deleted,
      :linked_user_id
    ])
    |> validate_required([:installation_id, :slack_user_id])
    |> unique_constraint([:installation_id, :slack_user_id])
  end
end
