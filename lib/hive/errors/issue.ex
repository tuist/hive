defmodule Hive.Errors.Issue do
  @moduledoc """
  A fingerprint-grouped error captured by the Sentry-compatible ingest
  endpoint. Every event with the same fingerprint rolls up into a single
  issue; the individual events live in ClickHouse (`errors_events`)
  and the mutable metadata (status, assignee, counts) lives here.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.User
  alias Hive.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses [:unresolved, :resolved, :ignored]
  @levels [:fatal, :error, :warning, :info, :debug]

  schema "errors_issues" do
    field :fingerprint, :string
    field :title, :string
    field :culprit, :string
    field :level, Ecto.Enum, values: @levels, default: :error
    field :platform, :string
    field :status, Ecto.Enum, values: @statuses, default: :unresolved
    field :first_seen, :utc_datetime_usec
    field :last_seen, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :event_count, :integer, default: 0

    belongs_to :project, Project
    belongs_to :assignee, User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def levels, do: @levels

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, [
      :project_id,
      :fingerprint,
      :title,
      :culprit,
      :level,
      :platform,
      :status,
      :first_seen,
      :last_seen,
      :resolved_at,
      :event_count,
      :assignee_id
    ])
    |> validate_required([:project_id, :fingerprint, :title, :first_seen, :last_seen])
    |> validate_length(:fingerprint, is: 64)
    |> validate_length(:title, max: 500)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:level, @levels)
    |> unique_constraint([:project_id, :fingerprint])
  end

  def status_changeset(issue, status) when status in @statuses do
    now = DateTime.utc_now()

    resolved_at =
      case status do
        :resolved -> now
        _ -> nil
      end

    change(issue, status: status, resolved_at: resolved_at)
  end
end
