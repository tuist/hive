defmodule Hive.Repo.Migrations.WidenVarcharColumnsToText do
  use Ecto.Migration

  # These columns were created as :string (varchar(255), Ecto's default) but
  # their changesets validate a longer max, so a value between 256 and the
  # validated max passes validation and then crashes the write with
  # 22001 string_data_right_truncation. Widen each to :text so the changeset
  # limit is the single source of truth. varchar(255)->text is a metadata-only
  # change (no table rewrite).
  #
  #   specs.summary          validated max 280
  #   projects.description   validated max 500
  #   drops.title            validated max 500
  #   drops.external_id      validated max 500
  def up do
    alter table(:specs) do
      modify :summary, :text
    end

    alter table(:projects) do
      modify :description, :text
    end

    alter table(:drops) do
      modify :title, :text
      modify :external_id, :text
    end
  end

  def down do
    alter table(:specs) do
      modify :summary, :string
    end

    alter table(:projects) do
      modify :description, :string
    end

    alter table(:drops) do
      modify :title, :string
      modify :external_id, :string
    end
  end
end
