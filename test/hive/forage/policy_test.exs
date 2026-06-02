defmodule Hive.Forage.PolicyTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hive.Accounts.User
  alias Hive.Auth
  alias Hive.Forage
  alias Hive.Forage.Policy

  defp public_source, do: Forage.get_source!(:feature_requests)
  defp org_source, do: Forage.get_source!(:grafana_alerts)
  defp user, do: %User{email: "alice@example.com"}

  describe "forage_source read" do
    test "a public source is readable by an anonymous visitor" do
      assert Policy.authorize?(:forage_source_read, nil, public_source())
    end

    test "an organization source is hidden from an anonymous visitor" do
      refute Policy.authorize?(:forage_source_read, nil, org_source())
    end

    test "an organization source is readable by a member" do
      stub(Auth, :member?, fn _user -> true end)

      assert Policy.authorize?(:forage_source_read, user(), org_source())
    end

    test "an organization source is hidden from an external contributor" do
      stub(Auth, :member?, fn _user -> false end)

      refute Policy.authorize?(:forage_source_read, user(), org_source())
    end
  end

  describe "forage_source create" do
    test "an anonymous visitor cannot create on a public source" do
      refute Policy.authorize?(:forage_source_create, nil, public_source())
    end

    test "an external contributor can create on a public creatable source" do
      stub(Auth, :member?, fn _user -> false end)

      assert Policy.authorize?(:forage_source_create, user(), public_source())
    end

    test "no one can create on a non-creatable source, even a member" do
      stub(Auth, :member?, fn _user -> true end)

      refute Policy.authorize?(:forage_source_create, user(), org_source())
    end
  end
end
