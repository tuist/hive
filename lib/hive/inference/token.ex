defmodule Hive.Inference.Token do
  @moduledoc """
  Hashed bearer token bound to one inference model binding.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Inference.ModelBinding
  alias Hive.Inference.Usage

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inference_tokens" do
    field :name, :string
    field :token_hash, :string, redact: true
    field :enabled, :boolean, default: true
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime

    belongs_to :model_binding, ModelBinding
    has_many :usages, Usage

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash, :enabled, :expires_at, :last_used_at])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name, :token_hash])
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:model_binding_id)
  end

  defp normalize_name(nil), do: nil

  defp normalize_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_name(value), do: value
end
