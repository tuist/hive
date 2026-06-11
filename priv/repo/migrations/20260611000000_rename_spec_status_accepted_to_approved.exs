defmodule Hive.Repo.Migrations.RenameSpecStatusAcceptedToApproved do
  use Ecto.Migration

  def up do
    execute("UPDATE specs SET status = 'approved' WHERE status = 'accepted'")
    execute("UPDATE spec_revisions SET status = 'approved' WHERE status = 'accepted'")
  end

  def down do
    execute("UPDATE specs SET status = 'accepted' WHERE status = 'approved'")
    execute("UPDATE spec_revisions SET status = 'accepted' WHERE status = 'approved'")
  end
end
