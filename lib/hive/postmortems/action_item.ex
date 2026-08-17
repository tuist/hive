defmodule Hive.Postmortems.ActionItem do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @priorities [:immediate, :high, :medium, :low]

  schema "postmortem_action_items" do
    field :title, :string
    field :description, :string
    field :priority, Ecto.Enum, values: @priorities, default: :medium
    field :completed_at, :utc_datetime

    belongs_to :postmortem, Hive.Postmortems.Postmortem

    timestamps(type: :utc_datetime)
  end

  def priorities, do: @priorities

  def changeset(action_item, attrs) do
    action_item
    |> cast(attrs, [:title, :description, :priority])
    |> validate_required([:title, :priority])
    |> validate_length(:title, min: 3, max: 500)
    |> validate_length(:description, max: 5_000)
    |> validate_inclusion(:priority, @priorities)
    |> foreign_key_constraint(:postmortem_id)
    |> check_constraint(:priority, name: :postmortem_action_items_priority_check)
  end
end
