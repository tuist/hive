defmodule Hive.Forage.GitHubIssueMeadow do
  @moduledoc false

  use Ecto.Schema

  alias Hive.Forage.GitHubIssue
  alias Hive.Meadows.Meadow

  @primary_key false
  @foreign_key_type :binary_id

  schema "forage_github_issue_meadows" do
    belongs_to :forage_github_issue, GitHubIssue, primary_key: true
    belongs_to :meadow, Meadow, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
