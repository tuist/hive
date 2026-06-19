defmodule Hive.Forage.Agents.GitHubIssueClassifierAgent do
  @moduledoc """
  Condukt agent that decides which domains a single GitHub issue belongs
  to. The candidate set is the domains attached to the issue's repository,
  so the answer is always a subset of that list (possibly empty).
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

  @issue_schema %{
    type: "object",
    properties: %{
      repository: %{type: "string"},
      number: %{type: "integer"},
      title: %{type: "string"},
      body: %{type: "string"}
    },
    required: ["repository", "title"],
    additionalProperties: false
  }

  @input_schema %{
    type: "object",
    properties: %{
      business_context: %{type: "string"},
      candidate_domains: %{type: "array", items: @domain_schema},
      issue: @issue_schema
    },
    required: ["business_context", "candidate_domains", "issue"],
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
    You assign GitHub issues to Hive domains.

    A domain is a durable business domain inside Tuist where forage items
    accumulate over time. Each domain has a name and a description. An
    issue belongs to a domain when the substance of the issue fits that
    domain, not when it simply happens to live in a repository that the
    domain is wired to.

    Rules:
    - Only pick domains from the candidate list. Do not invent ids.
    - Pick zero domains when none of the candidates fit. An empty list is
      the correct answer for unrelated issues, drive-by chatter, and
      issues whose substance is outside the candidate set.
    - Pick more than one domain only when the issue clearly spans them.
    - Be skeptical of repository-level signals. An issue in `tuist/tuist`
      is not automatically a Cache issue just because the Cache domain is
      attached to that repository; classify it as Cache only when its
      substance is about caching.
    - Read the title and body carefully. Prefer the strongest match over
      the loosest one.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:classify_issue,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Read the issue, compare it against the candidate domains' names and
    descriptions, and return the ids of the domains it belongs to in
    `domain_ids`. Return an empty list when none of the candidates fit.
    """
  )
end
