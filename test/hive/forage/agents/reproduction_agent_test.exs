defmodule Hive.Forage.Agents.ReproductionAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Forage.Agents.ReproductionAgent

  test "treats not reproduced as a valid successful objective outcome" do
    assert ReproductionAgent.tools() == Condukt.Tools.read_only_tools()
    assert ReproductionAgent.system_prompt() =~ "not-reproduced result is successful"

    assert ReproductionAgent.output_schema().properties.outcome.enum == [
             "reproduced",
             "not_reproduced",
             "inconclusive"
           ]
  end
end
