defmodule Hive.Specs.StyleGuideTest do
  use ExUnit.Case, async: true

  alias Hive.Specs.StyleGuide

  describe "body/0" do
    test "returns the spec writing guide with the canonical section spine" do
      body = StyleGuide.body()

      assert body =~ "Altitude"
      assert body =~ "Section spine"
      assert body =~ "Phase template"
      assert body =~ "What reviewers will push on"
      assert body =~ "Open questions"
      assert body =~ "Done-when"
    end

    test "names the implementation detail that does not belong in the spec" do
      body = StyleGuide.body()

      assert body =~ "Database DDL"
      assert body =~ "Lifecycle pseudocode"
      assert body =~ "Module paths and arities"
    end
  end

  describe "write_spec_prompt/1" do
    test "weaves the topic into the lede when one is provided" do
      prompt = StyleGuide.write_spec_prompt("Account invitations")

      assert prompt =~ "drafting a Hive spec about: Account invitations"
      assert prompt =~ "Altitude"
    end

    test "returns the guide cold when no topic is provided" do
      cold = StyleGuide.write_spec_prompt()

      assert cold =~ "about to draft a Hive spec"
      assert cold =~ "Altitude"
      refute cold =~ "drafting a Hive spec about:"
    end

    test "treats an empty topic the same as no topic" do
      assert StyleGuide.write_spec_prompt("") == StyleGuide.write_spec_prompt(nil)
    end
  end
end
