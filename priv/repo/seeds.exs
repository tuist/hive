# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias Hive.Repo
alias Hive.Accounts.User

# Create a seeded test user for development
case Repo.get_by(User, email: "test@hive.dev") do
  nil ->
    %User{}
    |> User.changeset(%{
      email: "test@hive.dev",
      name: "Test User"
    })
    |> Repo.insert!()

  _user ->
    :ok
end
