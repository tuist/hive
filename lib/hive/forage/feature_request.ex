defmodule Hive.Forage.FeatureRequest do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @types [:feature_request, :bug_report, :feedback]
  @statuses [:open, :planned, :closed]

  schema "forage_feature_requests" do
    field :type, Ecto.Enum, values: @types, default: :feature_request, source: :item_type
    field :title, :string
    field :description, :string
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :visibility, Ecto.Enum, values: [:public, :organization], default: :public

    belongs_to :user, Hive.Accounts.User
    has_many :comments, Hive.Forage.Comment, foreign_key: :forage_feature_request_id

    timestamps(type: :utc_datetime)
  end

  def types, do: @types
  def statuses, do: @statuses

  def changeset(feature_request, attrs) do
    feature_request
    |> cast(attrs, [:type, :title, :description])
    |> validate_required([:type, :title, :description])
    |> validate_inclusion(:type, @types)
    |> validate_length(:title, max: 160)
    |> validate_length(:description, min: 10, max: 2_000)
    |> put_change(:status, :open)
    |> put_change(:visibility, :public)
  end

  def update_changeset(feature_request, attrs) do
    feature_request
    |> cast(attrs, [:type, :title, :description])
    |> validate_required([:type, :title, :description])
    |> validate_inclusion(:type, @types)
    |> validate_length(:title, max: 160)
    |> validate_length(:description, min: 10, max: 2_000)
  end
end
