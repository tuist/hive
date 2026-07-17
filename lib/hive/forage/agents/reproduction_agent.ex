defmodule Hive.Forage.Agents.ReproductionAgent do
  @moduledoc """
  Attempts to reproduce a Forage item without publishing repository changes.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @output_schema %{
    type: "object",
    properties: %{
      outcome: %{
        type: "string",
        enum: ["reproduced", "not_reproduced", "inconclusive"]
      },
      summary: %{type: "string"},
      root_cause: %{type: "string"},
      validation: %{type: "array", items: %{type: "string"}}
    },
    required: ["outcome", "summary", "root_cause", "validation"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You attempt to reproduce product and operational signals in an isolated
    repository workspace. Read the repository instructions, derive the
    smallest faithful reproduction attempt, and run it. Record every relevant
    command and observation in the structured result.

    Do not edit files, commit, push, create a branch, or open a pull request.
    A not-reproduced result is successful when the stated attempts completed
    but did not exhibit the problem. Return inconclusive only when missing
    evidence or environment constraints prevent a meaningful attempt.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: Condukt.Tools.read_only_tools()

  def output_schema, do: @output_schema
end
