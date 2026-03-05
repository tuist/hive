defmodule Hive.Accounts do
  alias Hive.Repo
  alias Hive.Accounts.User

  def get_user(id), do: Repo.get(User, id)

  def find_or_create_user_from_auth(%Ueberauth.Auth{} = auth) do
    provider = to_string(auth.provider)
    uid = to_string(auth.uid)

    case Repo.get_by(User, provider: provider, provider_uid: uid) do
      nil ->
        %User{}
        |> User.changeset(%{
          email: auth.info.email,
          name: auth.info.name,
          avatar_url: auth.info.image,
          provider: provider,
          provider_uid: uid
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
