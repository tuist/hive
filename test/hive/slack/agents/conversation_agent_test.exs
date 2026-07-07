defmodule Hive.Slack.Agents.ConversationAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Agents.Tools.CreateForageItem
  alias Hive.Slack.Agents.ConversationAgent

  test "can create forage items through a tool" do
    assert ConversationAgent.tools() == [CreateForageItem]
  end
end
