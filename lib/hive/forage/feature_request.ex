defmodule Hive.Forage.FeatureRequest do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forage_feature_requests" do
    field :title, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:open, :planned, :closed], default: :open
    field :visibility, Ecto.Enum, values: [:public, :organization], default: :public

    belongs_to :user, Hive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(feature_request, attrs) do
    feature_request
    |> cast(attrs, [:title, :description])
    |> validate_required([:title, :description])
    |> validate_length(:title, max: 160)
    |> validate_length(:description, min: 10, max: 2_000)
    |> put_change(:status, :open)
    |> put_change(:visibility, :public)
  end
end
