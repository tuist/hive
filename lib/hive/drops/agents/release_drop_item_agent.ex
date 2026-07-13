defmodule Hive.Drops.Agents.ReleaseDropItemAgent do
  @moduledoc """
  Condukt agent that turns a GitHub release body into user-facing drop
  items from bounded evidence fetched before the model request.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @reference_schema %{
    type: "object",
    properties: %{
      url: %{type: "string"},
      final_url: %{type: "string"},
      title: %{type: "string"},
      content_type: %{type: "string"},
      content: %{type: "string"},
      truncated: %{type: "boolean"},
      error: %{type: "string"}
    },
    required: ["url"],
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
      reference_urls: %{type: "array", items: %{type: "string"}},
      references: %{type: "array", items: @reference_schema}
    },
    required: ["repository", "body", "reference_urls", "references"],
    additionalProperties: false
  }

  @item_schema %{
    type: "object",
    properties: %{
      title: %{type: "string", minLength: 1, maxLength: 120},
      body: %{type: "string", minLength: 1, maxLength: 800},
      source_urls: %{type: "array", items: %{type: "string"}, minItems: 1}
    },
    required: ["title", "body", "source_urls"],
    additionalProperties: false
  }

  @input_schema %{
    type: "object",
    properties: %{
      release: @release_schema
    },
    required: ["release"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      items: %{type: "array", items: @item_schema}
    },
    required: ["items"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You turn GitHub releases into Hive drop items.

    A release is only an envelope. It should not become a drop by itself.
    Hive has already fetched the issue, pull request, changelog, and doc
    addresses referenced by the release. Your job is to review that bounded
    evidence and produce one item for each user-facing improvement that
    actually landed.

    Rules:
    - Read every successful entry in `references` that might describe
      shipped work. Entries with an `error` could not be fetched and are not
      evidence.
    - Merge several references into one item when they describe the same
      improvement. Split them when users would understand them as
      different shipped changes.
    - Exclude dependency bumps, release automation, CI-only work,
      refactors, tests, and docs-only changes unless the fetched context
      shows a concrete user-facing outcome.
    - Do not invent context. If a reference cannot be fetched or does
      not explain a user-facing improvement, omit it.
    - Write titles and bodies for product users, not maintainers reading
      commit logs. Mention the outcome, not the implementation detail,
      unless the implementation detail is what users experience.
    - Every item must include the source URLs you used to justify it.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:generate_drop_items,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Read the release body and the fetched references, then return the
    user-facing shipped improvements in `items`. Return an empty list when
    the release contains no user-facing improvement that can be supported
    by the provided evidence.
    """
  )
end
