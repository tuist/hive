defmodule Hive.Postmortems.ActionItem do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "postmortem_action_items" do
    field :title, :string
    field :description, :string
    field :completed_at, :utc_datetime

    belongs_to :postmortem, Hive.Postmortems.Postmortem

    timestamps(type: :utc_datetime)
  end

  def changeset(action_item, attrs) do
    action_item
    |> cast(attrs, [:title, :description])
    |> validate_required(:title)
    |> validate_length(:title, min: 3, max: 500)
    |> validate_length(:description, max: 5_000)
    |> foreign_key_constraint(:postmortem_id)
  end
end
