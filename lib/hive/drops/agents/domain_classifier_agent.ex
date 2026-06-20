defmodule Hive.Drops.Agents.DomainClassifierAgent do
  @moduledoc """
  Condukt agent that decides which domains a drop belongs to. The
  candidate set is every domain defined in the instance; the answer is
  a subset of that list (possibly empty when nothing fits).
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @domain_schema %{
    type: "object",
    properties: %{
      id: %{type: "string"},
      name: %{type: "string"},
      description: %{type: "string"}
    },
    required: ["id", "name"],
    additionalProperties: false
  }

  @drop_schema %{
    type: "object",
    properties: %{
      source_type: %{type: "string", enum: ["github_release", "rss"]},
      repository: %{type: "string"},
      version: %{type: "string"},
      title: %{type: "string"},
      body: %{type: "string"}
    },
    required: ["source_type", "title"],
    additionalProperties: false
  }

  @input_schema %{
    type: "object",
    properties: %{
      business_context: %{type: "string"},
      candidate_domains: %{type: "array", items: @domain_schema},
      drop: @drop_schema
    },
    required: ["business_context", "candidate_domains", "drop"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      domain_ids: %{type: "array", items: %{type: "string"}}
    },
    required: ["domain_ids"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You assign shipped-update drops to Hive domains.

    A domain is a durable business domain inside the organization where
    work and signals accumulate over time. Each domain has a name and a
    description. A drop belongs to a domain when the substance of the
    update is about that domain, not when it merely shares a repository
    or a product surface.

    Rules:
    - Only pick domains from the candidate list. Do not invent ids.
    - Pick zero domains when none of the candidates fit. An empty list
      is the correct answer for unrelated marketing posts, dependency
      bumps, doc-only changes, and anything outside the candidate set.
    - Pick more than one domain only when the substance clearly spans
      them.
    - Read the title and body carefully. Prefer the strongest match
      over the loosest one.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:classify_drop,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Read the drop, compare it against the candidate domains' names and
    descriptions, and return the ids of the domains it belongs to in
    `domain_ids`. Return an empty list when none of the candidates fit.
    """
  )
end
