defmodule Hive.Slack.Agents.ConversationAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Agents.Tools.CreateForageItem
  alias Hive.Slack.Agents.ConversationAgent

  test "can create forage items through a tool" do
    assert ConversationAgent.tools() == [CreateForageItem]
  end

  test "build_prompt/1 renders the Slack thread context for a streamed reply" do
    prompt =
      ConversationAgent.build_prompt(%{
        "mention_text" => "<@U-bot> record this",
        "can_create_forage_item" => true,
        "available_github_labels" => [
          %{"name" => "bug", "description" => "Something broken"},
          %{"name" => "production"}
        ],
        "thread" => [
          %{"user" => "U1", "text" => "first", "ts" => "1.0"},
          %{"user" => "U2", "text" => "second", "ts" => "2.0"}
        ]
      })

    assert prompt =~ "Mention text:\n<@U-bot> record this"
    assert prompt =~ "Can create forage item:\ntrue"
    assert prompt =~ "- bug: Something broken"
    assert prompt =~ "- production"
    assert prompt =~ "- 1.0 U1: first"
    assert prompt =~ "- 2.0 U2: second"
    assert prompt =~ "Reply as normal Slack message text"
  end
end
