defmodule Hive.Meadows.Agents.EvolutionAgent do
  @moduledoc """
  Condukt agent that proposes how Hive's meadow taxonomy should evolve.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @input_schema %{
    type: "object",
    properties: %{
      business_context: %{type: "string"},
      current_meadows: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            id: %{type: "string"},
            name: %{type: "string"},
            description: %{type: "string"},
            visibility: %{type: "string"}
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
            meadows: %{type: "array", items: %{type: "string"}},
            occurred_at: %{type: "string"}
          },
          required: ["id", "kind", "title"]
        }
      }
    },
    required: ["business_context", "current_meadows", "work_items"]
  }

  @change_schema %{
    type: "object",
    properties: %{
      action: %{type: "string", enum: ["create", "update"]},
      meadow_id: %{type: "string"},
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
    You maintain Hive's list of meadows for Tuist.

    A meadow is a durable business domain where product specs, forage items,
    GitHub issues, and operational alerts can accumulate over time.

    Tuist's business domains include:
    - Apple platform developer workflows and Xcode project generation.
    - Build, cache, test, CI, and release automation for app teams.
    - Developer experience, documentation, onboarding, and CLI workflows.
    - Hive's own product planning, forage, specs, MCP, identity, and operations.
    - Noora's design system and product interface foundations.

    Taxonomy rules:
    - Prefer stable domains over individual features, bugs, alerts, or GitHub issues.
    - Do not create meadows for one command, one endpoint, one alert, one customer, or one ticket.
    - Do not create vague buckets such as Platform, Product, Infrastructure, or Operations.
    - Update an existing meadow when the signal refines a domain that already exists.
    - Create a new meadow only when several signals point to a durable domain that does not fit an existing meadow.
    - Keep meadow names short, concrete, and recognizable to Tuist contributors.
    - Keep descriptions operator-facing. Describe the domain, not the reason for this run.
    - Never delete meadows or change visibility.
    - Return an empty changes list when the existing taxonomy is already good.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:evolve_meadows,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Review the current meadows and recent work items.

    Propose only the meadow creations or updates that make the taxonomy better.
    Use action "update" with meadow_id when refining an existing meadow.
    Use action "create" only for a durable Tuist business domain that is neither too specific nor too generic.
    """
  )
end
