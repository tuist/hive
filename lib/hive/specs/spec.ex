defmodule Hive.Specs.Spec do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses [:draft, :proposed, :accepted, :in_progress, :shipped, :archived]

  schema "specs" do
    field :title, :string
    field :body, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :lock_version, :integer, default: 1

    belongs_to :source_feature_request, Hive.Forage.FeatureRequest
    belongs_to :created_by_user, Hive.Accounts.User
    belongs_to :updated_by_user, Hive.Accounts.User
    has_many :comments, Hive.Specs.Comment
    has_many :revisions, Hive.Specs.Revision

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(spec, attrs) do
    spec
    |> cast(attrs, [:title, :body, :status, :source_feature_request_id])
    |> validate_required([:title, :body, :status])
    |> validate_length(:title, max: 160)
    |> validate_length(:body, min: 10, max: 20_000)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:source_feature_request_id)
  end

  def update_changeset(spec, attrs) do
    spec
    |> changeset(attrs)
    |> optimistic_lock(:lock_version)
  end
end
