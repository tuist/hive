defmodule Hive.Forage.GitHubIssue do
  @moduledoc """
  Cached representation of a GitHub issue that the syncer pulled from the
  GitHub API. Only the fields the UI needs are persisted; richer metadata
  can be added later if more sources of work warrant it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Forage.GitHubIssueDomain
  alias Hive.Domains.GitHubRepository
  alias Hive.Drops.Drop
  alias Hive.Domains.Domain

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @states [:open, :closed]

  schema "forage_github_issues" do
    field :number, :integer
    field :title, :string
    field :body, :string
    field :state, Ecto.Enum, values: @states, default: :open
    field :classified_at, :utc_datetime

    belongs_to :github_repository, GitHubRepository

    many_to_many :domains, Domain,
      join_through: GitHubIssueDomain,
      join_keys: [forage_github_issue_id: :id, domain_id: :id]

    many_to_many :drops, Drop,
      join_through: Hive.Drops.DropGitHubIssue,
      join_keys: [forage_github_issue_id: :id, drop_id: :id]

    timestamps(type: :utc_datetime)
  end

  def states, do: @states

  def changeset(issue, attrs) do
    issue
    |> cast(attrs, [:github_repository_id, :number, :title, :body, :state, :classified_at])
    |> validate_required([:github_repository_id, :number, :title, :state])
    |> validate_length(:title, max: 500)
    |> validate_inclusion(:state, @states)
    |> unique_constraint([:github_repository_id, :number])
  end

  def html_url(%{github_repository: %GitHubRepository{owner: owner, name: name}, number: number}),
    do: "https://github.com/#{owner}/#{name}/issues/#{number}"
end
