defmodule Hive.Repo.Migrations.AddUniqueSlackUserProfileLinks do
  use Ecto.Migration

  def change do
    create unique_index(:slack_users, [:installation_id, :linked_user_id],
             where: "linked_user_id IS NOT NULL",
             name: :slack_users_one_linked_user_per_installation_index
           )
  end
end
