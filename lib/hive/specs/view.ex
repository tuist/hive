defmodule Hive.Specs.View do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spec_views" do
    field :last_viewed_at, :utc_datetime_usec

    belongs_to :spec, Hive.Specs.Spec
    belongs_to :user, Hive.Accounts.User

    timestamps(type: :utc_datetime)
  end
end
