defmodule Hive.Drops.DropDomain do
  @moduledoc false

  use Ecto.Schema

  alias Hive.Drops.Drop
  alias Hive.Domains.Domain

  @primary_key false
  @foreign_key_type :binary_id

  schema "drop_domains" do
    belongs_to :drop, Drop, primary_key: true
    belongs_to :domain, Domain, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
