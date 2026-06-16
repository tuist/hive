defmodule Hive.MCP.Components.Prompts.WriteSpecTest do
  use ExUnit.Case, async: true

  alias Hive.MCP.Components.Prompts.WriteSpec

  describe "behaviour metadata" do
    test "name is stable" do
      assert WriteSpec.name() == "write_spec"
    end

    test "description points at the use case" do
      assert WriteSpec.description() =~ "House style"
    end

    test "exposes an optional topic argument" do
      [topic] = WriteSpec.arguments()
      assert topic.name == "topic"
      assert topic.required == false
    end
  end

  describe "template/2" do
    test "returns a single user-role message containing the guide" do
      result = WriteSpec.template(nil, %{})

      assert [%{role: "user", content: %{type: "text", text: text}}] = result.messages
      assert text =~ "Altitude"
      assert text =~ "Section spine"
    end

    test "weaves the topic into the lede when provided" do
      result = WriteSpec.template(nil, %{"topic" => "Webhooks for system events"})

      [%{content: %{text: text}}] = result.messages
      assert text =~ "drafting a Hive spec about: Webhooks for system events"
    end

    test "falls back to a cold opener when topic is missing" do
      result = WriteSpec.template(nil, %{})

      [%{content: %{text: text}}] = result.messages
      assert text =~ "about to draft a Hive spec"
      refute text =~ "drafting a Hive spec about:"
    end
  end
end
