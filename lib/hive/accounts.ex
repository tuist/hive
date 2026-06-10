defmodule Hive.Accounts do
  @moduledoc """
  Persisted identities for people who sign in to the instance.

  Authentication is delegated to Ueberauth (see `Hive.Auth`); this
  context owns the `users` record we resolve on every successful login,
  plus the `user_identities` linking each provider login back to that
  user. A single person can sign in through several providers and still
  map to one user: an already-linked identity resolves straight to its
  owner, and only a never-seen identity falls back to matching by email.
  """

  alias Hive.Accounts.User
  alias Hive.Accounts.UserIdentity
  alias Hive.Repo

  @doc "Fetches a user by id, or `nil` when missing."
  def get_user(nil), do: nil
  def get_user(id), do: Repo.get(User, id)

  @doc "Fetches a user by id with its OAuth identities preloaded."
  def get_user_with_identities(nil), do: nil

  def get_user_with_identities(id) do
    User
    |> Repo.get(id)
    |> Repo.preload(:identities)
  end

  @doc "Fetches a user by email (case-insensitive), or `nil` when missing."
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: User.normalize_email(email))
  end

  @doc """
  Resolves an authenticated identity to a user, creating the user and/or
  the identity record as needed. An existing identity (matched by
  `{provider, provider_uid}`) resolves directly to its owner, so a
  provider that omits or changes the email still lands on the right user.
  Only a never-seen identity matches (or creates) a user by email. Runs
  in a transaction so a login never leaves a user without its identity.
  """
  def upsert_from_auth(%{email: email, provider: provider, provider_uid: provider_uid}) do
    Repo.transaction(fn ->
      case get_identity(provider, provider_uid) do
        %UserIdentity{} = identity ->
          identity |> Repo.preload(:user) |> Map.fetch!(:user)

        nil ->
          with {:ok, user} <- upsert_user(email),
               {:ok, _identity} <- insert_identity(user, provider, provider_uid) do
            user
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  @doc """
  Links an authenticated provider identity to an existing user.

  This is used from the account settings flow, where the person is
  already signed in and is connecting another provider. An identity that
  belongs to another user is left untouched.
  """
  def link_identity(%User{} = user, %{provider: provider, provider_uid: provider_uid}) do
    Repo.transaction(fn ->
      case upsert_identity(user, provider, provider_uid) do
        {:ok, %UserIdentity{user_id: user_id}} when user_id == user.id -> user
        {:ok, %UserIdentity{}} -> Repo.rollback(:identity_already_linked)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp upsert_user(email) do
    case get_user_by_email(email || "") do
      nil -> %User{} |> User.changeset(%{email: email}) |> Repo.insert()
      user -> {:ok, user}
    end
  end

  defp upsert_identity(user, provider, provider_uid) do
    case get_identity(provider, provider_uid) do
      nil -> insert_identity(user, provider, provider_uid)
      identity -> {:ok, identity}
    end
  end

  defp insert_identity(user, provider, provider_uid) do
    %UserIdentity{}
    |> UserIdentity.changeset(%{
      provider: provider,
      provider_uid: provider_uid,
      user_id: user.id
    })
    |> Repo.insert()
  end

  defp get_identity(provider, provider_uid) do
    Repo.get_by(UserIdentity, provider: provider, provider_uid: provider_uid)
  end
end
