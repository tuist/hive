defmodule Hive.Repo.Migrations.ChangeAvatarUrlToText do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :avatar_url, :text, from: :string
    end
  end
end
