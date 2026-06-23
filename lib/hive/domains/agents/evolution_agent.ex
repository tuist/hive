defmodule Hive.Domains.Agents.EvolutionAgent do
  @moduledoc """
  Condukt agent that proposes how Hive's domain taxonomy should evolve.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @input_schema %{
    type: "object",
    properties: %{
      business_context: %{type: "string"},
      current_projects: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            id: %{type: "string"},
            name: %{type: "string"}
          },
          required: ["id", "name"]
        }
      },
      current_domains: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            id: %{type: "string"},
            name: %{type: "string"},
            description: %{type: "string"},
            visibility: %{type: "string"},
            projects: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{
                  id: %{type: "string"},
                  name: %{type: "string"}
                },
                required: ["id", "name"]
              }
            }
          },
          required: ["id", "name", "visibility"]
        }
      },
      work_items: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            id: %{type: "string"},
            kind: %{type: "string"},
            title: %{type: "string"},
            body: %{type: "string"},
            status: %{type: "string"},
            source: %{type: "string"},
            domains: %{type: "array", items: %{type: "string"}},
            projects: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{
                  id: %{type: "string"},
                  name: %{type: "string"}
                },
                required: ["id", "name"]
              }
            },
            occurred_at: %{type: "string"}
          },
          required: ["id", "kind", "title"]
        }
      }
    },
    required: ["business_context", "current_projects", "current_domains", "work_items"]
  }

  @change_schema %{
    type: "object",
    properties: %{
      action: %{type: "string", enum: ["create", "update"]},
      domain_id: %{type: "string"},
      project_ids: %{type: "array", items: %{type: "string"}, maxItems: 5},
      name: %{type: "string", minLength: 2, maxLength: 120},
      description: %{type: "string", minLength: 20, maxLength: 500},
      rationale: %{type: "string", minLength: 10, maxLength: 400}
    },
    required: ["action", "name", "description", "rationale"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      changes: %{
        type: "array",
        maxItems: 8,
        items: @change_schema
      }
    },
    required: ["changes"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You maintain Hive's list of domains for Tuist.

    A domain is a durable business domain where product specs, forage items,
    GitHub issues, and operational alerts can accumulate over time.

    Tuist's business domains include:
    - Infrastructure for productive software development.
    - Build automation, remote caching, testing, CI, and release workflows.
    - Compute environments that make development and automation faster.
    - Build system support across Xcode, Gradle, Bazel, and related ecosystems.
    - Developer experience, documentation, onboarding, and CLI workflows.
    - Atlas operations workflows and infrastructure.
    - Hive's own product planning, forage, specs, MCP, identity, and operations.
    - Once distribution and self-hosted product operations.

    Taxonomy rules:
    - Prefer stable domains over individual features, bugs, alerts, or GitHub issues.
    - Do not create domains for one command, one endpoint, one alert, one customer, or one ticket.
    - Do not create vague buckets such as Platform, Product, Infrastructure, or Operations.
    - Update an existing domain when the signal refines a domain that already exists.
    - Create a new domain only when several signals point to a durable domain that does not fit an existing domain.
    - For create actions, include project_ids from the supporting work items.
    - When a created domain applies to more than one project, include every matching project identifier.
    - Keep domain names short, concrete, and recognizable to Tuist contributors.
    - Keep descriptions operator-facing. Describe the domain, not the reason for this run.
    - Never delete domains or change visibility.
    - Return an empty changes list when the existing taxonomy is already good.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:evolve_domains,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Review the current domains and recent work items.

    Propose only the domain creations or updates that make the taxonomy better.
    Use action "update" with domain_id when refining an existing domain.
    Use action "create" only for a durable Tuist business domain that is neither too specific nor too generic.
    For create actions, include project_ids using only identifiers present in current_projects.
    """
  )
end
