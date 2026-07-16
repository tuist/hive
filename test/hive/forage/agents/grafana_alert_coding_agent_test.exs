defmodule Hive.Forage.Agents.GrafanaAlertCodingAgentTest do
  use ExUnit.Case, async: true

  alias Hive.Forage.Agents.GrafanaAlertCodingAgent

  test "exposes sandbox-aware coding tools and a structured result" do
    assert GrafanaAlertCodingAgent.tools() == Condukt.Tools.coding_tools()
    assert GrafanaAlertCodingAgent.system_prompt() =~ "Do not commit, push, create a branch"

    schema = GrafanaAlertCodingAgent.output_schema()
    assert schema.required == ["outcome", "summary", "root_cause", "validation"]
    assert schema.properties.outcome.enum == ["changed", "no_change", "blocked"]
  end
end
