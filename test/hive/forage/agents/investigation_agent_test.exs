defmodule Hive.Forage.Agents.InvestigationAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Forage.Agents.InvestigationAgent

  test "uses repository tools but forbids changes and publication" do
    assert InvestigationAgent.tools() == Condukt.Tools.read_only_tools()
    assert InvestigationAgent.system_prompt() =~ "Do not edit files"

    assert InvestigationAgent.output_schema().properties.outcome.enum == [
             "investigated",
             "inconclusive"
           ]
  end
end
