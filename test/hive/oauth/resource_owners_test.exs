defmodule Hive.OAuth.ResourceOwnersTest do
  use Hive.DataCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias Hive.Accounts
  alias Hive.OAuth.ResourceOwners

  describe "get_by/1" do
    test "returns a resource owner by normalized username" do
      {:ok, user} = signed_in("alice@example.com")

      assert {:ok, %ResourceOwner{sub: sub, username: "alice@example.com"}} =
               ResourceOwners.get_by(username: "Alice@Example.COM")

      assert sub == user.id
    end

    test "returns a resource owner by subject" do
      {:ok, user} = signed_in("alice@example.com")

      assert {:ok, %ResourceOwner{sub: sub, username: "alice@example.com"}} =
               ResourceOwners.get_by(sub: user.id)

      assert sub == user.id
    end

    test "returns an error for an unknown username" do
      assert ResourceOwners.get_by(username: "nobody@example.com") == {:error, "User not found."}
    end

    test "returns an error for an unknown subject" do
      assert ResourceOwners.get_by(sub: Ecto.UUID.generate()) == {:error, "User not found."}
    end
  end

  test "check_password/2 rejects password authentication" do
    resource_owner = %ResourceOwner{sub: Ecto.UUID.generate(), username: "alice@example.com"}

    assert ResourceOwners.check_password(resource_owner, "secret") ==
             {:error, "Password authentication is not supported."}
  end

  test "authorized_scopes/1 returns no pre-authorized scopes" do
    resource_owner = %ResourceOwner{sub: Ecto.UUID.generate(), username: "alice@example.com"}

    assert ResourceOwners.authorized_scopes(resource_owner) == []
  end

  test "claims/2 exposes the email claim from the resource owner username" do
    resource_owner = %ResourceOwner{sub: Ecto.UUID.generate(), username: "alice@example.com"}

    assert ResourceOwners.claims(resource_owner, "mcp") == %{email: "alice@example.com"}
  end

  defp signed_in(email) do
    Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})
  end
end
