defmodule Hive.Specs.Revision do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spec_revisions" do
    field :revision, :integer
    field :title, :string
    field :body, :string
    field :summary, :string
    field :status, Ecto.Enum, values: Hive.Specs.Spec.statuses()

    belongs_to :spec, Hive.Specs.Spec
    belongs_to :user, Hive.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:revision, :title, :body, :summary, :status, :spec_id, :user_id])
    |> validate_required([:revision, :title, :body, :status, :spec_id])
    |> unique_constraint([:spec_id, :revision])
    |> foreign_key_constraint(:spec_id)
  end

  def summary_changeset(revision, summary) when is_binary(summary) do
    revision
    |> cast(%{summary: summary}, [:summary])
    |> validate_required([:summary])
    |> validate_length(:summary, max: 500)
  end
end
