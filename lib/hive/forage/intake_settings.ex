defmodule Hive.Forage.IntakeSettings do
  @moduledoc """
  Runtime-managed forage intake settings.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Domains.GitHubRepository

  @destinations [:hive_item, :github_issue]
  @empty_github_repository_id_value "__none__"
  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :binary_id

  schema "forage_intake_settings" do
    field :destination, Ecto.Enum, values: @destinations, default: :hive_item

    belongs_to :github_repository, GitHubRepository

    timestamps(type: :utc_datetime)
  end

  def destinations, do: @destinations
  def empty_github_repository_id_value, do: @empty_github_repository_id_value

  def changeset(settings, attrs) do
    settings
    |> cast(normalize_github_repository_id(attrs), [:destination, :github_repository_id])
    |> validate_required([:id, :destination])
    |> validate_github_repository()
    |> foreign_key_constraint(:github_repository_id)
  end

  defp normalize_github_repository_id(attrs) when is_map(attrs) do
    attrs
    |> normalize_github_repository_id("github_repository_id")
    |> normalize_github_repository_id(:github_repository_id)
  end

  defp normalize_github_repository_id(attrs), do: attrs

  defp normalize_github_repository_id(attrs, key) do
    if Map.get(attrs, key) in ["", @empty_github_repository_id_value] do
      Map.put(attrs, key, nil)
    else
      attrs
    end
  end

  defp validate_github_repository(changeset) do
    if get_field(changeset, :destination) == :github_issue do
      validate_required(changeset, [:github_repository_id])
    else
      changeset
    end
  end
end
