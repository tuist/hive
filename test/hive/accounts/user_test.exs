defmodule Hive.Accounts.UserTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts.User

  describe "changeset/2" do
    test "is valid with an email" do
      changeset = User.changeset(%User{}, %{email: "alice@example.com"})

      assert changeset.valid?
    end

    test "requires an email" do
      changeset = User.changeset(%User{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:email]
    end

    test "normalizes the email to trimmed lowercase" do
      changeset = User.changeset(%User{}, %{email: "  Alice@Example.COM  "})

      assert get_change(changeset, :email) == "alice@example.com"
    end

    test "rejects an email longer than 160 characters" do
      changeset = User.changeset(%User{}, %{email: String.duplicate("a", 161) <> "@example.com"})

      refute changeset.valid?
      assert {"should be at most %{count} character(s)", _} = changeset.errors[:email]
    end

    test "enforces email uniqueness at insert time" do
      assert {:ok, _} = %User{} |> User.changeset(%{email: "alice@example.com"}) |> Repo.insert()

      assert {:error, changeset} =
               %User{} |> User.changeset(%{email: "alice@example.com"}) |> Repo.insert()

      assert {"has already been taken", _} = changeset.errors[:email]
    end

    test "uniqueness is case-insensitive thanks to normalization" do
      assert {:ok, _} = %User{} |> User.changeset(%{email: "alice@example.com"}) |> Repo.insert()

      assert {:error, changeset} =
               %User{} |> User.changeset(%{email: "ALICE@Example.com"}) |> Repo.insert()

      assert {"has already been taken", _} = changeset.errors[:email]
    end
  end
end
