defmodule Hive.Forage.Policy.ChecksTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hive.Accounts.User
  alias Hive.Auth
  alias Hive.Forage.Policy.Checks

  describe "public_source/2" do
    test "is true for a public source and false otherwise" do
      assert Checks.public_source(nil, %{visibility: :public})
      refute Checks.public_source(nil, %{visibility: :organization})
      refute Checks.public_source(nil, %{})
    end
  end

  describe "creatable_source/2" do
    test "is true only when the source is creatable" do
      assert Checks.creatable_source(nil, %{creatable?: true})
      refute Checks.creatable_source(nil, %{creatable?: false})
      refute Checks.creatable_source(nil, %{})
    end
  end

  describe "org_member/2" do
    test "delegates to Auth.member?" do
      stub(Auth, :member?, fn _user -> true end)
      assert Checks.org_member(%User{}, %{})

      stub(Auth, :member?, fn _user -> false end)
      refute Checks.org_member(%User{}, %{})
    end
  end

  describe "authenticated/2" do
    test "is true for a user and false for an anonymous visitor" do
      assert Checks.authenticated(%User{}, %{})
      refute Checks.authenticated(nil, %{})
    end
  end
end
