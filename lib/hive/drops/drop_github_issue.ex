defmodule Hive.Drops.DropGitHubIssue do
  @moduledoc false

  use Ecto.Schema

  alias Hive.Drops.Drop
  alias Hive.Forage.GitHubIssue

  @primary_key false
  @foreign_key_type :binary_id

  schema "drop_github_issues" do
    belongs_to :drop, Drop, primary_key: true
    belongs_to :forage_github_issue, GitHubIssue, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
