defmodule Hive.Repo.Migrations.BackfillForageGithubIssueMeadows do
  use Ecto.Migration

  @doc """
  Seeds `forage_github_issue_meadows` from the existing repository →
  meadow wiring so issues cached before the classifier shipped keep
  their meadow grouping in the dashboard. `classified_at` is left null
  on every row, so the sweeper still runs each issue through the agent
  on the next tick and replaces these backfilled rows with the real
  classification.
  """
  def up do
    execute("""
    INSERT INTO forage_github_issue_meadows
      (forage_github_issue_id, meadow_id, inserted_at, updated_at)
    SELECT issue.id,
           link.meadow_id,
           NOW() AT TIME ZONE 'UTC',
           NOW() AT TIME ZONE 'UTC'
    FROM forage_github_issues issue
    INNER JOIN meadows_github_repositories link
      ON link.github_repository_id = issue.github_repository_id
    ON CONFLICT DO NOTHING
    """)
  end

  def down do
    :ok
  end
end
