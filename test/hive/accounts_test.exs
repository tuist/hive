defmodule Hive.AccountsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Accounts.UserIdentity

  describe "upsert_from_auth/1" do
    test "creates a user and its identity" do
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

    test "rejects a blank email" do
      assert {:error, %Ecto.Changeset{}} =
               Accounts.upsert_from_auth(%{email: nil, provider: "github", provider_uid: "gh-9"})

      assert Repo.aggregate(UserIdentity, :count) == 0
    end

    test "normalizes the email to lowercase" do
      {:ok, user} =
        Accounts.upsert_from_auth(%{
          email: "Alice@Example.COM",
          provider: "google",
          provider_uid: "g-1"
        })

      assert user.email == "alice@example.com"
    end
  end

  describe "get_user/1" do
    test "returns the user with the given id" do
      {:ok, user} = signed_in("alice@example.com")

      assert Accounts.get_user(user.id).id == user.id
    end

    test "returns nil for an unknown id" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end

    test "returns nil for a nil id" do
      assert Accounts.get_user(nil) == nil
    end
  end

  describe "get_user_by_email/1" do
    test "returns the user, matching case-insensitively" do
      {:ok, user} = signed_in("alice@example.com")

      assert Accounts.get_user_by_email("ALICE@Example.com").id == user.id
    end

    test "returns nil when no user matches" do
      assert Accounts.get_user_by_email("nobody@example.com") == nil
    end
  end

  defp signed_in(email) do
    Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})
  end
end
