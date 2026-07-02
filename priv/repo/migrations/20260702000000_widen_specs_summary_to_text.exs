defmodule Hive.Repo.Migrations.WidenSpecsSummaryToText do
  use Ecto.Migration

  # The summary changeset allows up to 280 chars but the column was varchar(255)
  # (Ecto's :string default), so a 256-280 char summary passed validation and
  # then crashed the insert with 22001 string_data_right_truncation. Widen to
  # :text so the changeset limit is the single source of truth, matching body
  # and the other free-form text columns.
  def up do
    alter table(:specs) do
      modify :summary, :text
    end
  end

  def down do
    alter table(:specs) do
      modify :summary, :string
    end
  end
end
