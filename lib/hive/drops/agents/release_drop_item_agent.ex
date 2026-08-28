defmodule Hive.Drops.Agents.ReleaseDropItemAgent do
  @moduledoc """
  Condukt agent that turns bounded GitHub release evidence into individual,
  user-facing drop items.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @reference_schema %{
    type: "object",
    properties: %{
      url: %{type: "string"},
      number: %{type: "integer"},
      title: %{type: "string"},
      body: %{type: "string"},
      state: %{type: "string"}
    },
    required: ["url", "number", "title", "body", "state"],
    additionalProperties: false
  }

  @release_schema %{
    type: "object",
    properties: %{
      repository: %{type: "string"},
      tag: %{type: "string"},
      title: %{type: "string"},
      body: %{type: "string"},
      url: %{type: "string"},
      published_at: %{type: "string"},
      references: %{type: "array", items: @reference_schema, maxItems: 6}
    },
    required: ["repository", "body", "references"],
    additionalProperties: false
  }

  @item_schema %{
    type: "object",
    properties: %{
      title: %{type: "string", minLength: 1, maxLength: 120},
      body: %{type: "string", minLength: 1, maxLength: 800},
      source_urls: %{type: "array", items: %{type: "string"}, minItems: 1, maxItems: 6}
    },
    required: ["title", "body", "source_urls"],
    additionalProperties: false
  }

  @input_schema %{
    type: "object",
    properties: %{release: @release_schema},
    required: ["release"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{items: %{type: "array", items: @item_schema, maxItems: 6}},
    required: ["items"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You turn GitHub releases into individual Hive drop items.

    Evidence contains the release notes and directly referenced GitHub issues
    or pull requests. Produce one item for each concrete user-facing feature
    supported by that evidence. Do not combine unrelated features. Exclude
    dependency bumps, release automation, continuous-integration-only work,
    refactors, tests, and documentation-only changes unless the evidence shows
    a concrete user-facing outcome.

    Use only the supplied source URLs. Do not invent context or links. Return
    an empty list when no user-facing feature is supported by the evidence.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:generate_drop_items,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Use the structured release and reference evidence to return at most six
    distinct user-facing shipped improvements in `items`.
    """
  )
end
