defmodule Hive.Inference.ModelBinding do
  @moduledoc """
  A stable model name exposed by Hive's inference relay.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Inference.ModelIdentifier

  @name_format ~r/^[A-Za-z0-9][A-Za-z0-9._:-]*$/

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inference_model_bindings" do
    field :name, :string
    field :description, :string
    field :upstream_provider, :string
    field :upstream_model, :string
    field :input_cost_per_million, :decimal
    field :output_cost_per_million, :decimal
    field :enabled, :boolean, default: true
    field :hive_inference, :boolean, default: false
    field :hive_coding, :boolean, default: false
    field :hive_embedding, :boolean, default: false
    field :last_used_at, :utc_datetime

    has_many :tokens, Hive.Inference.Token, foreign_key: :model_binding_id
    has_many :usages, Hive.Inference.Usage, foreign_key: :model_binding_id

    timestamps(type: :utc_datetime)
  end

  def changeset(binding, attrs) do
    binding
    |> cast(attrs, [
      :name,
      :description,
      :upstream_provider,
      :upstream_model,
      :input_cost_per_million,
      :output_cost_per_million,
      :enabled,
      :hive_inference,
      :hive_coding,
      :hive_embedding,
      :last_used_at
    ])
    |> normalize_strings([:name, :upstream_provider, :upstream_model])
    |> validate_required([:name, :upstream_provider, :upstream_model])
    |> validate_format(:name, @name_format)
    |> validate_model_identifier()
    |> validate_number(:input_cost_per_million, greater_than_or_equal_to: 0)
    |> validate_number(:output_cost_per_million, greater_than_or_equal_to: 0)
    |> unique_constraint(:name)
    |> unique_constraint(:hive_inference,
      name: :inference_model_bindings_single_hive_inference_index,
      message: "is already assigned to another profile"
    )
    |> unique_constraint(:hive_coding,
      name: :inference_model_bindings_single_hive_coding_index,
      message: "is already assigned to another profile"
    )
    |> unique_constraint(:hive_embedding,
      name: :inference_model_bindings_single_hive_embedding_index,
      message: "is already assigned to another profile"
    )
  end

  defp validate_model_identifier(changeset) do
    validate_change(changeset, :upstream_model, fn :upstream_model, value ->
      validate_model_identifier(value, get_field(changeset, :upstream_provider))
    end)
  end

  defp validate_model_identifier(value, selected_provider) do
    value
    |> ModelIdentifier.upstream_model(selected_provider)
    |> ModelIdentifier.model_path?()
    |> case do
      true ->
        []

      false ->
        [upstream_model: "must be a provider model identifier, for example gpt-4o-mini"]
    end
  end

  defp normalize_strings(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_string/1)
    end)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_string(value), do: value
end
