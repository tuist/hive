defmodule Hive.Projects.Project do
  @moduledoc """
  A project is the top-level grouping in Hive: a product, codebase, or
  service the instance tracks. Projects own their connected GitHub
  repositories and the RSS sources whose entries feed their domains.
  Domains are reusable tags that may be associated with multiple
  projects.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @visibilities [:public, :private]

  schema "projects" do
    field :name, :string
    field :description, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :public

    many_to_many :domains, Hive.Domains.Domain,
      join_through: Hive.Projects.ProjectDomain,
      join_keys: [project_id: :id, domain_id: :id]

    has_many :github_repositories, Hive.Domains.GitHubRepository
    has_many :drop_sources, Hive.Drops.DropSource
    has_many :webhooks, Hive.Projects.Webhook

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :visibility])
    |> normalize_string(:name)
    |> normalize_string(:description)
    |> validate_required([:name, :visibility])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint(:name)
  end

  defp normalize_string(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) ->
        value
        |> String.trim()
        |> blank_to_nil()

      value ->
        value
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
