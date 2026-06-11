defmodule Hive.Specs.Spec do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses [:draft, :proposed, :approved, :paused, :rejected, :in_progress, :shipped, :archived]
  @visibilities [:public, :private]

  schema "specs" do
    field :number, :integer, read_after_writes: true
    field :title, :string
    field :body, :string
    field :summary, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :lock_version, :integer, default: 1
    field :product_ids, {:array, :binary_id}, virtual: true

    belongs_to :source_feature_request, Hive.Forage.FeatureRequest
    belongs_to :created_by_user, Hive.Accounts.User
    belongs_to :updated_by_user, Hive.Accounts.User
    has_many :comments, Hive.Specs.Comment
    has_many :revisions, Hive.Specs.Revision

    many_to_many :products, Hive.Products.Product,
      join_through: "products_specs",
      join_keys: [spec_id: :id, product_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def visibilities, do: @visibilities

  def changeset(spec, attrs) do
    attrs = normalize_product_ids(attrs)

    spec
    |> cast(attrs, [
      :title,
      :body,
      :summary,
      :status,
      :visibility,
      :source_feature_request_id,
      :product_ids
    ])
    |> validate_required([:title, :body, :status, :visibility])
    |> validate_length(:title, max: 160)
    |> validate_length(:summary, max: 280)
    |> validate_length(:body, min: 10, max: 20_000)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_change(:summary, fn
      :summary, summary when is_binary(summary) ->
        if String.contains?(summary, "—"),
          do: [summary: "cannot contain em dashes"],
          else: []

      :summary, _summary ->
        []
    end)
    |> foreign_key_constraint(:source_feature_request_id)
  end

  def update_changeset(spec, attrs) do
    spec
    |> changeset(attrs)
    |> optimistic_lock(:lock_version)
  end

  defp normalize_product_ids(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, "product_ids") ->
        Map.put(attrs, "product_ids", normalize_product_id_values(attrs["product_ids"]))

      Map.has_key?(attrs, :product_ids) ->
        Map.put(attrs, :product_ids, normalize_product_id_values(attrs.product_ids))

      true ->
        attrs
    end
  end

  defp normalize_product_ids(attrs), do: attrs

  defp normalize_product_id_values(values) do
    values
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end
end
