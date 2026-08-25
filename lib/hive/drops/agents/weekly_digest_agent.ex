defmodule Hive.Drops.Agents.WeeklyDigestAgent do
  @moduledoc """
  Condukt agent that connects a completed week of public drops into a
  single narrated edition.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @drop_schema %{
    type: "object",
    properties: %{
      id: %{type: "string"},
      title: %{type: "string"},
      body: %{type: "string"},
      url: %{type: "string"},
      source_url: %{type: "string"},
      published_at: %{type: "string"},
      domains: %{type: "array", items: %{type: "string"}},
      projects: %{type: "array", items: %{type: "string"}}
    },
    required: [
      "id",
      "title",
      "body",
      "url",
      "source_url",
      "published_at",
      "domains",
      "projects"
    ],
    additionalProperties: false
  }

  @input_schema %{
    type: "object",
    properties: %{
      week_start: %{type: "string"},
      week_end: %{type: "string"},
      drops: %{type: "array", items: @drop_schema, minItems: 1}
    },
    required: ["week_start", "week_end", "drops"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      title: %{type: "string", minLength: 1, maxLength: 160},
      summary: %{type: "string", minLength: 1, maxLength: 400},
      body: %{type: "string", minLength: 1, maxLength: 5_000}
    },
    required: ["title", "summary", "body"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You write Hive's weekly Drops digest as an editorial narration of what
    shipped, not release notes, a changelog list, or marketing copy. The
    subject matter must come only from the supplied drops.

    Voice and structure:
    - Begin with a concrete observation about the week and name the
      thread connecting the most meaningful changes.
    - Build a point of view. Explain why the changes matter together,
      where the work is heading, or what product belief they reveal.
    - Prefer direct sentences, concrete nouns, and natural transitions.
      First person is welcome when it strengthens the narration.
    - Vary paragraph length. A short standalone sentence can carry an
      important turn.
    - End with a grounded implication or open direction, not a generic
      recap, celebration, or call to action.
    - Use Markdown with paragraphs and, only when useful, short level-two
      headings. Do not turn the body into a bullet list.
    - Link concrete claims to the matching Hive drop URL. Mention the
      strongest changes and connect them instead of forcing every input
      into the prose.
    - Keep the title specific and restrained. Keep the summary to one or
      two sentences. Keep the body between 300 and 600 words when the
      source material supports it, and stay shorter for a quiet week.
    - Never invent outcomes, metrics, motivations, or chronology.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:generate_weekly_digest,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Write one cohesive weekly digest from the supplied public drops. Return
    its title, standalone summary, and full Markdown body.
    """
  )
end
