defmodule Hive.OAuth.ScopesTest do
  use ExUnit.Case, async: true

  alias Hive.OAuth.Scopes

  describe "expand/1" do
    test "returns nil unchanged" do
      assert Scopes.expand(nil) == nil
    end

    test "returns an empty string unchanged" do
      assert Scopes.expand("") == ""
    end

    test "expands the mobile umbrella into its granular scopes" do
      assert Scopes.expand("mobile") ==
               "mobile.me.read mobile.forage.read mobile.specs.read mobile.drops.read mobile.errors.read"
    end

    test "leaves non-umbrella scopes untouched" do
      assert Scopes.expand("mcp api") == "mcp api"
    end

    test "combines umbrella expansion with other scopes and preserves order" do
      assert Scopes.expand("api mobile mcp") ==
               "api mobile.me.read mobile.forage.read mobile.specs.read mobile.drops.read mobile.errors.read mcp"
    end

    test "deduplicates when both the umbrella and a granular scope appear" do
      assert Scopes.expand("mobile.me.read mobile") ==
               "mobile.me.read mobile.forage.read mobile.specs.read mobile.drops.read mobile.errors.read"
    end
  end

  describe "mobile_scopes/0" do
    test "returns the concrete list" do
      assert Scopes.mobile_scopes() == [
               "mobile.me.read",
               "mobile.forage.read",
               "mobile.specs.read",
               "mobile.drops.read",
               "mobile.errors.read"
             ]
    end
  end
end
