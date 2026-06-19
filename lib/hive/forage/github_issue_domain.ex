defmodule Hive.Forage.GitHubIssueDomain do
  @moduledoc false

  use Ecto.Schema

  alias Hive.Forage.GitHubIssue
  alias Hive.Domains.Domain

  @primary_key false
  @foreign_key_type :binary_id

  schema "forage_github_issue_domains" do
    belongs_to :forage_github_issue, GitHubIssue, primary_key: true
    belongs_to :domain, Domain, primary_key: true

    timestamps(type: :utc_datetime)
  end
end
