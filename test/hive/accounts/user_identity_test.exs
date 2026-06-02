defmodule Hive.Accounts.UserIdentityTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts.User
  alias Hive.Accounts.UserIdentity

  setup do
    {:ok, user} = %User{} |> User.changeset(%{email: "alice@example.com"}) |> Repo.insert()
    %{user: user}
  end

  describe "changeset/2" do
    test "is valid with provider, provider_uid, and user_id", %{user: user} do
      changeset =
        UserIdentity.changeset(%UserIdentity{}, %{
          provider: "google",
          provider_uid: "g-1",
          user_id: user.id
        })

      assert changeset.valid?
    end

    test "requires provider, provider_uid, and user_id" do
      changeset = UserIdentity.changeset(%UserIdentity{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:provider]
      assert {"can't be blank", _} = changeset.errors[:provider_uid]
      assert {"can't be blank", _} = changeset.errors[:user_id]
    end

    test "enforces uniqueness of provider + provider_uid at insert time", %{user: user} do
      attrs = %{provider: "google", provider_uid: "g-1", user_id: user.id}

      assert {:ok, _} = %UserIdentity{} |> UserIdentity.changeset(attrs) |> Repo.insert()

      assert {:error, changeset} =
               %UserIdentity{} |> UserIdentity.changeset(attrs) |> Repo.insert()

      assert {"has already been taken", _} = changeset.errors[:provider]
    end

    test "the same provider_uid under a different provider is allowed", %{user: user} do
      assert {:ok, _} =
               %UserIdentity{}
               |> UserIdentity.changeset(%{
                 provider: "google",
                 provider_uid: "1",
                 user_id: user.id
               })
               |> Repo.insert()

      assert {:ok, _} =
               %UserIdentity{}
               |> UserIdentity.changeset(%{
                 provider: "github",
                 provider_uid: "1",
                 user_id: user.id
               })
               |> Repo.insert()
    end
  end
end
