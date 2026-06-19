defmodule Hive.Drops.DropMeadow do
  @moduledoc false

  use Ecto.Schema

  alias Hive.Drops.Drop
  alias Hive.Meadows.Meadow

  @primary_key false
  @foreign_key_type :binary_id

  schema "drop_meadows" do
    belongs_to :drop, Drop, primary_key: true
    belongs_to :meadow, Meadow, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
