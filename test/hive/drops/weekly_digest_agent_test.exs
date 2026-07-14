defmodule Hive.Drops.WeeklyDigestAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Drops.Agents.WeeklyDigestAgent

  test "requires grounded narration without list-like, em-dash prose" do
    prompt = WeeklyDigestAgent.system_prompt()

    assert prompt =~ "subject matter must come only from the supplied drops"
    assert prompt =~ "not release"
    assert prompt =~ "notes, a changelog list"
    assert prompt =~ "Do not turn the body into a bullet list"
    assert prompt =~ "Never use em dashes"
    refute prompt =~ "—"
    assert WeeklyDigestAgent.tools() == []
  end
end
