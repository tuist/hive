defmodule Hive.Specs.Spec do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @statuses [:draft, :proposed, :approved, :paused, :rejected, :in_progress, :shipped, :archived]
  @visibilities [:public, :private]

  schema "specs" do
    field :number, :integer
    field :title, :string
    field :body, :string
    field :summary, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :lock_version, :integer, default: 1
    field :domain_ids, {:array, :binary_id}, virtual: true
    field :last_activity_at, :utc_datetime, virtual: true
    field :has_new_activity, :boolean, virtual: true, default: false

    belongs_to :source_feature_request, Hive.Forage.FeatureRequest
    belongs_to :created_by_user, Hive.Accounts.User
    belongs_to :updated_by_user, Hive.Accounts.User
    has_many :comments, Hive.Specs.Comment
    has_many :revisions, Hive.Specs.Revision

    many_to_many :domains, Hive.Domains.Domain,
      join_through: "domains_specs",
      join_keys: [spec_id: :id, domain_id: :id],
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def visibilities, do: @visibilities

  def changeset(spec, attrs) do
    attrs = normalize_domain_ids(attrs)

    spec
    |> cast(attrs, [
      :title,
      :body,
      :summary,
      :status,
      :visibility,
      :source_feature_request_id,
      :domain_ids
    ])
    |> validate_required([:title, :body, :status, :visibility])
    |> validate_length(:title, max: 160)
    |> validate_length(:summary, max: 280)
    |> validate_length(:body, min: 10, max: 100_000)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint(:number)
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

  defp normalize_domain_ids(attrs) when is_map(attrs) do
    cond do
      Map.has_key?(attrs, "domain_ids") ->
        Map.put(attrs, "domain_ids", normalize_domain_id_values(attrs["domain_ids"]))

      Map.has_key?(attrs, :domain_ids) ->
        Map.put(attrs, :domain_ids, normalize_domain_id_values(attrs.domain_ids))

      true ->
        attrs
    end
  end

  defp normalize_domain_ids(attrs), do: attrs

  defp normalize_domain_id_values(values) do
    values
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end
end
