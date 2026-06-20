defmodule Hive.Drops.PolicyTest do
  use ExUnit.Case, async: true

  alias Hive.Accounts.User
  alias Hive.Drops.Drop
  alias Hive.Drops.Policy
  alias Hive.Domains.Domain

  describe "drop_read" do
    test "anyone can read drops that touch a public domain" do
      drop = %Drop{domains: [%Domain{visibility: :public}]}
      assert Policy.authorize?(:drop_read, nil, drop)
      assert Policy.authorize?(:drop_read, %User{role: :collaborator}, drop)
    end

    test "only members can read drops that touch only private domains" do
      drop = %Drop{domains: [%Domain{visibility: :private}]}
      refute Policy.authorize?(:drop_read, nil, drop)
      refute Policy.authorize?(:drop_read, %User{role: :collaborator}, drop)
      assert Policy.authorize?(:drop_read, %User{role: :member}, drop)
      assert Policy.authorize?(:drop_read, %User{role: :admin}, drop)
    end

    test "unclassified drops are members-only" do
      drop = %Drop{domains: []}
      refute Policy.authorize?(:drop_read, nil, drop)
      assert Policy.authorize?(:drop_read, %User{role: :member}, drop)
    end
  end
end
