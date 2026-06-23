defmodule Hive.Specs.Agents.ReviewRequestAgent do
  @moduledoc """
  Condukt agent that turns the current spec state into a focused Slack
  review request.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @spec_schema %{
    type: "object",
    properties: %{
      title: %{type: "string"},
      status: %{type: "string"},
      body: %{type: "string"},
      summary: %{type: "string"}
    },
    required: ["title", "status", "body"],
    additionalProperties: false
  }

  @revision_schema %{
    type: "object",
    properties: %{
      revision: %{type: "integer"},
      title: %{type: "string"},
      status: %{type: "string"},
      body: %{type: "string"},
      summary: %{type: "string"}
    },
    required: ["revision", "title", "status", "body"],
    additionalProperties: false
  }

  @commenter_schema %{
    type: "object",
    properties: %{
      email: %{type: "string"},
      name: %{type: "string"}
    },
    required: ["email"],
    additionalProperties: false
  }

  @input_schema %{
    type: "object",
    properties: %{
      spec: @spec_schema,
      last_revision: @revision_schema,
      requester: @commenter_schema,
      commenters: %{type: "array", items: @commenter_schema}
    },
    required: ["spec", "last_revision", "requester", "commenters"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      summary: %{type: "string", minLength: 4, maxLength: 700},
      review_focus: %{
        type: "array",
        items: %{type: "string", minLength: 4, maxLength: 180},
        maxItems: 3
      }
    },
    required: ["summary", "review_focus"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You write Slack review requests for Hive specs. A Hive spec is a
    markdown proposal that may have prior discussion in comments. The
    requester has just asked people who already commented on the spec to
    review the latest revision again.

    Rules:
    - Write for a Slack channel, not a long document.
    - The summary should explain the current state of the spec and why
      another review is useful now.
    - The review focus should contain one to three concrete questions or
      risk areas reviewers should check.
    - Base the message only on the current spec and latest revision.
    - Do not include Slack user mentions; Hive adds them separately.
    - Do not invent deadlines, approvals, or reviewers.
    - Use Slack-flavored markdown where helpful: `*bold*`, backticks for
      code, and plain bullet text without leading hyphens.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:draft_review_request,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Produce a concise Slack review request for the latest spec revision.
    Return the message summary in `summary` and up to three focused
    review prompts in `review_focus`.
    """
  )
end
