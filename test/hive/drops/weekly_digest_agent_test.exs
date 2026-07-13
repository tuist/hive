defmodule Hive.Drops.WeeklyDigestAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Agents.Tools.FetchUrlContent
  alias Hive.Drops.Agents.WeeklyDigestAgent

  test "samples public writing and forbids list-like, em-dash prose" do
    prompt = WeeklyDigestAgent.system_prompt()

    assert prompt =~ "read every provided style"
    assert prompt =~ "sample. Learn the writing patterns"
    assert prompt =~ "not release"
    assert prompt =~ "notes, a changelog list"
    assert prompt =~ "Do not turn the body into a bullet list"
    assert prompt =~ "Never use em dashes"
    refute prompt =~ "—"
    assert WeeklyDigestAgent.tools() == [FetchUrlContent]
  end
end
