defmodule Hive.Drops.WeeklyDigest do
  @moduledoc """
  A durable, model-generated narration of the public drops published in
  one Monday-to-Friday workweek.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses [:generating, :published, :empty, :failed]
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "drop_weekly_digests" do
    field :week_start, :date
    field :week_end, :date
    field :status, Ecto.Enum, values: @statuses
    field :title, :string
    field :summary, :string
    field :body, :string
    field :drop_ids, {:array, Ecto.UUID}, default: []
    field :published_at, :utc_datetime
    field :failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(digest, attrs) do
    digest
    |> cast(attrs, [
      :week_start,
      :week_end,
      :status,
      :title,
      :summary,
      :body,
      :drop_ids,
      :published_at,
      :failure_reason
    ])
    |> validate_required([:week_start, :week_end, :status, :drop_ids])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:title, max: 160)
    |> validate_length(:summary, max: 400)
    |> validate_length(:body, max: 20_000)
    |> validate_length(:failure_reason, max: 500)
    |> validate_week_range()
    |> validate_published_content()
    |> unique_constraint(:week_start)
  end

  defp validate_week_range(changeset) do
    start_date = get_field(changeset, :week_start)
    end_date = get_field(changeset, :week_end)

    if match?(%Date{}, start_date) and match?(%Date{}, end_date) and
         Date.diff(end_date, start_date) != 4 do
      add_error(changeset, :week_end, "must finish four days after the week starts")
    else
      changeset
    end
  end

  defp validate_published_content(changeset) do
    if get_field(changeset, :status) == :published do
      validate_required(changeset, [:title, :summary, :body, :published_at])
    else
      changeset
    end
  end
end
