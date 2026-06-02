defmodule Hive.AccountsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Accounts.UserIdentity

  test "upsert_from_auth creates a user and its identity" do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "google",
        provider_uid: "g-1"
      })

    assert user.email == "alice@example.com"
    assert [%UserIdentity{provider: "google", provider_uid: "g-1"}] = Repo.all(UserIdentity)
  end

  test "the same person signing in through two providers maps to one user with two identities" do
    {:ok, first} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "google",
        provider_uid: "g-1"
      })

    {:ok, second} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "github",
        provider_uid: "gh-9"
      })

    assert first.id == second.id
    assert Repo.aggregate(UserIdentity, :count) == 2
  end

  test "signing in again with the same identity is idempotent" do
    attrs = %{email: "alice@example.com", provider: "github", provider_uid: "gh-9"}

    {:ok, first} = Accounts.upsert_from_auth(attrs)
    {:ok, again} = Accounts.upsert_from_auth(attrs)

    assert first.id == again.id
    assert Repo.aggregate(UserIdentity, :count) == 1
  end

  test "upsert_from_auth rejects a blank email" do
    assert {:error, %Ecto.Changeset{}} =
             Accounts.upsert_from_auth(%{email: nil, provider: "github", provider_uid: "gh-9"})
  end

  test "email is normalized to lowercase" do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "Alice@Example.COM",
        provider: "google",
        provider_uid: "g-1"
      })

    assert user.email == "alice@example.com"
    assert Accounts.get_user_by_email("alice@example.com").id == user.id
  end
end
