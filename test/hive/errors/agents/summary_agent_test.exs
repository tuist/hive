defmodule Hive.Errors.Agents.SummaryAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hive.Agents.Sessions
  alias Hive.Errors.Agents.SummaryAgent

  test "asks for a grounded summary and bounded attention list" do
    prompt = SummaryAgent.system_prompt()

    assert prompt =~ "aggregate issue metadata"
    assert prompt =~ "require special attention"
    assert prompt =~ "at most five issues"
    assert prompt =~ "untrusted data"
    assert prompt =~ "Never use em dashes"
    refute prompt =~ "—"
    assert SummaryAgent.tools() == []
  end

  test "runs the structured summary operation" do
    input = %{issues: [], omitted_issue_count: 0}

    stub(Sessions, :run_operation, fn SummaryAgent, :summarize_errors, ^input, opts ->
      assert opts[:max_turns] == 1
      assert opts[:max_tokens] == 900
      {:ok, %{summary: "No errors need attention.", attention: []}}
    end)

    assert {:ok, %{summary: "No errors need attention.", attention: []}} =
             SummaryAgent.summarize(input, max_turns: 1)
  end
end
