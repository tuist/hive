defmodule Hive.Specs.Agents.RevisionSummaryAgent do
  @moduledoc """
  Condukt agent that turns a spec revision diff into a short, human
  readable summary of what actually changed.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @revision_schema %{
    type: "object",
    properties: %{
      title: %{type: "string"},
      status: %{type: "string"}
    },
    required: ["title", "status"],
    additionalProperties: false
  }

  @input_schema %{
    type: "object",
    properties: %{
      previous: @revision_schema,
      current: @revision_schema,
      body_diff: %{type: "string"}
    },
    required: ["previous", "current", "body_diff"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      summary: %{type: "string", minLength: 4, maxLength: 500}
    },
    required: ["summary"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You explain what changed between two revisions of a Hive spec to the
    operators and contributors who are reading the spec's draft history.

    A spec is a markdown proposal with a title, a status, and a body that
    describes a problem, a proposal, the tradeoffs considered, and the
    acceptance criteria. Each revision is a saved snapshot of those
    fields. The history view already shows the revision number, who
    edited it, and when, so the summary should only describe the substance
    of the edit.

    The body is provided as a line-oriented diff. Lines beginning with `-`
    were removed, lines beginning with `+` were added, and unmarked context
    lines are unchanged.

    Rules:
    - Write one or two sentences in past tense, starting with a verb.
    - Be specific about what the editor actually changed: which sections,
      which claims, which acceptance criteria, which tradeoffs.
    - Mention title and status changes when they happen, but do not
      restate counts of added or removed lines.
    - Do not invent details that are not visible in the two revisions.
    - When the change is purely cosmetic (whitespace, formatting,
      reflow), say so plainly.
    - Do not address the reader and do not include preamble like
      "This revision".

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:summarize_revision,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Compare the previous and current revisions and produce a concise
    summary of what changed in the spec's substance. Return the summary
    in the `summary` field.
    """
  )
end
