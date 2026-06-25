defmodule Hive.Repo.Migrations.CreateInferenceProviders do
  use Ecto.Migration

  def change do
    create table(:inference_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :base_url, :string, null: false
      add :api_key_ciphertext, :text
      add :timeout, :integer, null: false, default: 300_000

      timestamps(type: :utc_datetime)
    end

    create unique_index(:inference_providers, [:key])
  end
end
