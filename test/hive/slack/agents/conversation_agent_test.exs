defmodule Hive.Slack.Agents.ConversationAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Agents.Tools.CreateForageItem
  alias Hive.Agents.Tools.ListGitHubLabels
  alias Hive.Slack.Agents.ConversationAgent

  test "can create forage items through a tool" do
    assert ConversationAgent.tools() == [ListGitHubLabels, CreateForageItem]
  end

  test "instructs forage capture to remove sensitive and identifying information" do
    prompt = ConversationAgent.system_prompt()

    assert prompt =~ "Never include who"
    assert prompt =~ "people's names, Slack"
    assert prompt =~ "customer or account"
    assert prompt =~ "technical behavior, generalized impact"
    assert prompt =~ "Omit `source_url`"

    assert CreateForageItem.description() =~
             "exclude sensitive details and any information identifying who"
  end

  test "build_prompt/1 renders the Slack thread context for a streamed reply" do
    prompt =
      ConversationAgent.build_prompt(%{
        "can_create_forage_item" => true,
        "slack_profile_link" => "https://hive.example/account/slack/new",
        "thread" => [
          %{"user" => "U1", "text" => "first", "ts" => "1.0"},
          %{
            "user" => "U2",
            "text" => "<@U-bot> record this",
            "ts" => "2.0",
            "triggering_mention" => true
          }
        ]
      })

    assert prompt =~ "Can create forage item:\ntrue"

    assert prompt =~
             "<https://hive.example/account/slack/new|Connect your Slack profile>"

    assert prompt =~ "- 1.0 U1: first"
    assert prompt =~ "- [triggering mention] 2.0 U2: <@U-bot> record this"
    assert length(:binary.matches(prompt, "<@U-bot> record this")) == 1
    assert prompt =~ "Reply as normal Slack message text"
  end
end
