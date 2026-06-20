defmodule Hive.Drops.DropSource do
  @moduledoc """
  Operator-registered changelog source. Currently only RSS/Atom URLs
  are supported. Sources belong to a project; each ingested entry is
  classified into one or more of that project's domains by
  `Hive.Drops.DomainClassification`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @types [:rss]
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "drop_sources" do
    field :type, Ecto.Enum, values: @types, default: :rss
    field :url, :string
    field :label, :string
    field :enabled, :boolean, default: true
    field :last_polled_at, :utc_datetime
    field :last_error, :string
    field :last_error_at, :utc_datetime

    belongs_to :project, Hive.Projects.Project

    timestamps(type: :utc_datetime)
  end

  def types, do: @types

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:type, :url, :label, :enabled, :project_id])
    |> normalize_url()
    |> normalize_label()
    |> validate_required([:type, :url, :project_id])
    |> validate_inclusion(:type, @types)
    |> validate_length(:url, max: 2000)
    |> validate_length(:label, max: 120)
    |> validate_format(:url, ~r/^https?:\/\//, message: "must be an http(s) URL")
    |> unique_constraint(:url, message: "already registered")
    |> foreign_key_constraint(:project_id)
  end

  def poll_changeset(source, attrs) do
    source
    |> cast(attrs, [:last_polled_at, :last_error, :last_error_at])
  end

  defp normalize_url(changeset) do
    update_change(changeset, :url, fn
      value when is_binary(value) -> value |> String.trim() |> blank_to_nil()
      value -> value
    end)
  end

  defp normalize_label(changeset) do
    update_change(changeset, :label, fn
      value when is_binary(value) -> value |> String.trim() |> blank_to_nil()
      value -> value
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
