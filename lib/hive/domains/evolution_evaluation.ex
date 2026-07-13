defmodule Hive.Domains.EvolutionEvaluation do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "domain_evolution_evaluations" do
    field :fingerprint, :string
    field :outcome, Ecto.Enum, values: [:changed, :noop]
    field :work_items_count, :integer
    field :created_count, :integer
    field :updated_count, :integer
    field :skipped_count, :integer
    field :evaluated_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(evaluation, attrs) do
    evaluation
    |> cast(attrs, [
      :fingerprint,
      :outcome,
      :work_items_count,
      :created_count,
      :updated_count,
      :skipped_count,
      :evaluated_at
    ])
    |> validate_required([
      :fingerprint,
      :outcome,
      :work_items_count,
      :created_count,
      :updated_count,
      :skipped_count,
      :evaluated_at
    ])
    |> validate_length(:fingerprint, is: 64)
    |> validate_number(:work_items_count, greater_than_or_equal_to: 0)
    |> validate_number(:created_count, greater_than_or_equal_to: 0)
    |> validate_number(:updated_count, greater_than_or_equal_to: 0)
    |> validate_number(:skipped_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:fingerprint)
  end
end
