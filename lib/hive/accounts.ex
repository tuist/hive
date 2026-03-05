defmodule Hive.Accounts do
  alias Hive.Repo
  alias Hive.Accounts.User

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def find_or_create_user_from_auth(%Ueberauth.Auth{} = auth) do
    email = auth.info.email

    case Repo.get_by(User, email: email) do
      nil ->
        %User{}
        |> User.changeset(%{
          email: email,
          name: auth.info.name,
          avatar_url: auth.info.image
        })
        |> Repo.insert()

      user ->
        user
        |> User.changeset(%{
          name: auth.info.name,
          avatar_url: auth.info.image
        })
        |> Repo.update()
    end
  end
end
