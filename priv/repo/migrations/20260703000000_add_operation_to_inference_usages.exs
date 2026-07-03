defmodule Hive.Repo.Migrations.AddOperationToInferenceUsages do
  use Ecto.Migration

  def change do
    alter table(:inference_usages) do
      add :operation, :string, null: false, default: "chat_completion"
    end

    create index(:inference_usages, [:operation, :inserted_at])
  end
end
