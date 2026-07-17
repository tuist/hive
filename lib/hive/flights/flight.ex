defmodule Hive.Flights.Flight do
  @moduledoc """
  A durable agent execution connected to the product signal that prompted it.

  Flights preserve their input, outcome, and portable agent session after the
  execution sandbox has been destroyed.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses [:queued, :running, :succeeded, :failed]
  @objectives [:investigate, :reproduce, :fix]
  @objective_outcomes [
    :investigated,
    :reproduced,
    :not_reproduced,
    :fixed,
    :no_change,
    :inconclusive
  ]

  schema "flights" do
    field :forage_item_id, :string
    field :status, Ecto.Enum, values: @statuses
    field :objective, Ecto.Enum, values: @objectives, default: :investigate
    field :objective_outcome, Ecto.Enum, values: @objective_outcomes
    field :trigger, :map, default: %{}
    field :runner, :string
    field :runner_id, :string
    field :repository_full_name, :string
    field :input, :map, default: %{}
    field :session, :map
    field :result, :map
    field :error, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :forage_item, :map, virtual: true

    belongs_to :repository, Hive.Domains.GitHubRepository
    belongs_to :requested_by, Hive.Accounts.User
    belongs_to :parent_flight, __MODULE__

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def objectives, do: @objectives
  def objective_outcomes, do: @objective_outcomes

  def changeset(flight, attrs) do
    flight
    |> cast(attrs, [
      :forage_item_id,
      :status,
      :objective,
      :objective_outcome,
      :trigger,
      :runner,
      :runner_id,
      :repository_full_name,
      :input,
      :session,
      :result,
      :error,
      :started_at,
      :completed_at,
      :repository_id,
      :requested_by_id,
      :parent_flight_id
    ])
    |> validate_required([
      :forage_item_id,
      :status,
      :objective,
      :runner,
      :repository_full_name,
      :input
    ])
    |> require_repository_on_insert(flight)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:objective, @objectives)
    |> validate_inclusion(:objective_outcome, @objective_outcomes)
    |> validate_length(:runner, max: 100)
    |> validate_length(:repository_full_name, max: 255)
    |> validate_length(:runner_id, max: 255)
    |> unique_constraint([:forage_item_id, :repository_id], name: :flights_one_active_run)
    |> foreign_key_constraint(:repository_id)
    |> foreign_key_constraint(:requested_by_id)
    |> foreign_key_constraint(:parent_flight_id)
  end

  defp require_repository_on_insert(changeset, %__MODULE__{id: nil}) do
    validate_required(changeset, [:repository_id])
  end

  defp require_repository_on_insert(changeset, %__MODULE__{}), do: changeset
end
