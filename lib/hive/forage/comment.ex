defmodule Hive.Forage.Comment do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "forage_item_comments" do
    field :body, :string

    belongs_to :feature_request, Hive.Forage.FeatureRequest,
      foreign_key: :forage_feature_request_id

    belongs_to :user, Hive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 2, max: 20_000)
    |> foreign_key_constraint(:forage_feature_request_id)
  end
end
