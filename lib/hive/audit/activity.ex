defmodule Hive.Audit.Activity do
  @moduledoc """
  A single recorded entry in the audit trail. See `Hive.Audit` for the
  context that records and queries these.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.User

  @interfaces ~w(dashboard inference mcp webhook worker system)
  @actor_kinds ~w(user agent system)
  @string_fields [
    :action,
    :interface,
    :actor_kind,
    :actor_email,
    :actor_name,
    :actor_role,
    :target_type,
    :target_id,
    :target_label
  ]

  @derive {
    Flop.Schema,
    filterable: [
      :action,
      :interface,
      :actor_kind,
      :actor_id,
      :actor_email,
      :target_type,
      :target_id
    ],
    sortable: [:occurred_at, :inserted_at],
    default_limit: 25,
    max_limit: 100
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_activities" do
    field :action, :string
    field :interface, :string
    field :occurred_at, :utc_datetime
    field :actor_kind, :string, default: "system"
    field :actor_email, :string
    field :actor_name, :string
    field :actor_role, :string
    field :target_type, :string
    field :target_id, :string
    field :target_label, :string
    field :metadata, :map, default: %{}

    belongs_to :actor, User

    timestamps(type: :utc_datetime)
  end

  def interfaces, do: @interfaces
  def actor_kinds, do: @actor_kinds

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [
      :action,
      :interface,
      :occurred_at,
      :actor_kind,
      :actor_id,
      :actor_email,
      :actor_name,
      :actor_role,
      :target_type,
      :target_id,
      :target_label,
      :metadata
    ])
    |> put_default_occurred_at()
    |> normalize_string_fields()
    |> infer_actor_kind()
    |> validate_required([:action, :interface, :occurred_at, :actor_kind])
    |> validate_inclusion(:interface, @interfaces)
    |> validate_inclusion(:actor_kind, @actor_kinds)
    |> foreign_key_constraint(:actor_id)
  end

  defp infer_actor_kind(changeset) do
    case get_field(changeset, :actor_kind) do
      kind when is_binary(kind) and kind != "" ->
        changeset

      _empty ->
        kind = if get_field(changeset, :actor_id), do: "user", else: "system"
        put_change(changeset, :actor_kind, kind)
    end
  end

  defp put_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _occurred_at -> changeset
    end
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce(@string_fields, changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_string/1)
    end)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: to_string(value)
end
