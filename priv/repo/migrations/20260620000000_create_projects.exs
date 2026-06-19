defmodule Hive.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:name])

    alter table(:meadows) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
    end

    alter table(:github_repositories) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :nilify_all)
    end

    alter table(:drop_sources) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all)
    end

    create index(:meadows, [:project_id])
    create index(:github_repositories, [:project_id])
    create index(:drop_sources, [:project_id])

    flush()

    # Backfill: one project per existing meadow. Inherit name, description,
    # and visibility from the meadow. Existing repos linked through the
    # meadow_github_repositories join move to the meadow's project. When a
    # repo is shared across meadows, the first meadow we encounter wins,
    # matching what an operator would do manually when collapsing the
    # association.
    execute(
      """
      INSERT INTO projects (id, name, description, visibility, inserted_at, updated_at)
      SELECT
        gen_random_uuid(),
        meadows.name,
        meadows.description,
        meadows.visibility,
        meadows.inserted_at,
        meadows.updated_at
      FROM meadows
      """,
      ""
    )

    execute(
      """
      UPDATE meadows
      SET project_id = projects.id
      FROM projects
      WHERE projects.name = meadows.name
      """,
      ""
    )

    execute(
      """
      UPDATE github_repositories AS gr
      SET project_id = m.project_id
      FROM meadows_github_repositories AS link
      JOIN meadows AS m ON m.id = link.meadow_id
      WHERE link.github_repository_id = gr.id
        AND gr.project_id IS NULL
      """,
      ""
    )

    execute(
      """
      ALTER TABLE meadows
      ALTER COLUMN project_id SET NOT NULL
      """,
      """
      ALTER TABLE meadows
      ALTER COLUMN project_id DROP NOT NULL
      """
    )

    drop_if_exists table(:meadows_github_repositories)
  end
end
