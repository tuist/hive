defmodule Hive.Forage.CodingRun do
  @moduledoc """
  A durable coding-harness execution for a Forage item.

  The item and result are deliberately represented as typed maps so the
  workflow can grow beyond Grafana alerts and pull requests without changing
  the execution lifecycle.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses [:queued, :running, :succeeded, :failed]

  schema "forage_coding_runs" do
    field :forage_item_id, :string
    field :status, Ecto.Enum, values: @statuses
    field :runner, :string
    field :runner_id, :string
    field :repository_full_name, :string
    field :input, :map, default: %{}
    field :result, :map
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :repository, Hive.Domains.GitHubRepository
    belongs_to :requested_by, Hive.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :forage_item_id,
      :status,
      :runner,
      :runner_id,
      :repository_full_name,
      :input,
      :result,
      :error,
      :started_at,
      :completed_at,
      :repository_id,
      :requested_by_id
    ])
    |> validate_required([
      :forage_item_id,
      :status,
      :runner,
      :repository_full_name,
      :input,
      :repository_id
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:runner, max: 100)
    |> validate_length(:repository_full_name, max: 255)
    |> validate_length(:runner_id, max: 255)
    |> unique_constraint([:forage_item_id, :repository_id],
      name: :forage_coding_runs_one_active_run
    )
    |> foreign_key_constraint(:repository_id)
    |> foreign_key_constraint(:requested_by_id)
  end
end
