defmodule Hive.OAuth.ResourceOwners do
  @moduledoc false

  @behaviour Boruta.Oauth.ResourceOwners

  alias Boruta.Oauth.ResourceOwner
  alias Hive.Accounts.User
  alias Hive.Repo

  @impl Boruta.Oauth.ResourceOwners
  def get_by(attrs) when is_list(attrs) do
    cond do
      username = attrs[:username] ->
        get_by_username(username)

      sub = attrs[:sub] ->
        get_by_sub(sub)
    end
  end

  defp get_by_username(username) when is_binary(username) do
    case Repo.get_by(User, email: User.normalize_email(username)) do
      %User{} = user -> {:ok, resource_owner(user)}
      nil -> {:error, "User not found."}
    end
  end

  defp get_by_sub(sub) when is_binary(sub) do
    case Repo.get(User, sub) do
      %User{} = user -> {:ok, resource_owner(user)}
      nil -> {:error, "User not found."}
    end
  end

  @impl Boruta.Oauth.ResourceOwners
  def check_password(_resource_owner, _password),
    do: {:error, "Password authentication is not supported."}

  @impl Boruta.Oauth.ResourceOwners
  def authorized_scopes(%ResourceOwner{}), do: []

  @impl Boruta.Oauth.ResourceOwners
  def claims(%ResourceOwner{username: email}, _scope), do: %{email: email}

  defp resource_owner(%User{id: id, email: email}) do
    %ResourceOwner{sub: id, username: email}
  end
end
