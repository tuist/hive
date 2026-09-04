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

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  # UUIDv5 namespace scoped to Hive errors issues. Fixed for the life of
  # the schema — changing it renames every issue id in the deployment,
  # so treat it as a schema constant.
  @uuid_namespace <<0x6F, 0x66, 0xEA, 0xF6, 0x2C, 0x18, 0x5C, 0x11, 0xA5, 0xB2, 0xD1, 0xF4, 0x5D,
                    0x8D, 0x22, 0x1A>>

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

  @doc """
  Deterministic UUIDv5-shaped id for the issue that groups events with
  this `fingerprint` inside `project_id`. Same inputs always produce
  the same id, so `Hive.Errors.record_event/2` can build the
  ClickHouse row (which references `issue_id`) without a Postgres
  round-trip to the `errors_issues` row.

  RFC 4122 §4.3 UUIDv5: SHA-1 of `namespace <> name`, with version and
  variant bits forced into place. `name` = `project_id <> ":" <> fingerprint`.
  """
  @spec deterministic_id(binary(), binary()) :: Ecto.UUID.t()
  def deterministic_id(project_id, fingerprint)
      when is_binary(project_id) and is_binary(fingerprint) do
    name = project_id <> ":" <> fingerprint

    <<time_low::32, time_mid::16, _::4, time_hi::12, _::2, clock_hi::14, node::48, _rest::binary>> =
      :crypto.hash(:sha, @uuid_namespace <> name)

    binary = <<time_low::32, time_mid::16, 5::4, time_hi::12, 2::2, clock_hi::14, node::48>>
    Ecto.UUID.cast!(binary)
  end

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, [
      :id,
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
    |> put_deterministic_id_if_missing()
    |> validate_required([:id, :project_id, :fingerprint, :title, :first_seen, :last_seen])
    |> validate_length(:fingerprint, is: 64)
    |> validate_length(:title, max: 500)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:level, @levels)
    |> unique_constraint([:project_id, :fingerprint])
  end

  # Safety net for callers that don't set the id explicitly (e.g. test
  # factories, one-off scripts). When both `project_id` and
  # `fingerprint` are present, compute the deterministic id so a plain
  # `Repo.insert` still produces the same row `Hive.Errors.record_event/2`
  # would.
  defp put_deterministic_id_if_missing(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      project_id = get_field(changeset, :project_id)
      fingerprint = get_field(changeset, :fingerprint)

      if project_id && fingerprint do
        put_change(changeset, :id, deterministic_id(project_id, fingerprint))
      else
        changeset
      end
    end
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
