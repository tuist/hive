defmodule Hive.Drops.Agents.ReleaseRewriterAgent do
  @moduledoc """
  Condukt agent that rewrites a GitHub release body into user-facing
  markdown for the drops dashboard.

  GitHub release notes are written for contributors: they reference PR
  numbers, author handles, internal labels, and process artefacts. The
  agent is given the raw release body plus the `fetch_url_content` tool
  so it can navigate the issues, pull requests, and other links the
  body cites to understand what each change actually delivers, then
  rewrite the substance for the product's user.
  """

  use Condukt

  alias Hive.Agents.StyleGuide
  alias Hive.Agents.Tools.FetchUrlContent

  @input_schema %{
    type: "object",
    properties: %{
      meadow: %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          description: %{type: "string"}
        },
        required: ["name"],
        additionalProperties: false
      },
      repository: %{type: "string"},
      release: %{
        type: "object",
        properties: %{
          tag: %{type: "string"},
          name: %{type: "string"},
          url: %{type: "string"},
          body: %{type: "string"}
        },
        required: ["body"],
        additionalProperties: false
      }
    },
    required: ["meadow", "release"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      body: %{
        type: "string",
        description:
          "User-facing markdown body for the release. Concise, no PR numbers, no contributor handles, no internal labels."
      }
    },
    required: ["body"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You rewrite GitHub release notes into user-facing changelog entries
    for the Hive "drops" dashboard.

    Source release notes are written for contributors and tend to leak
    internals: pull-request numbers, author handles, internal labels,
    "thanks @x" callouts, merge commit hashes, and bot-generated
    summaries. Your job is to translate the substance of those notes
    into what the *user* of the product sees: what changed, what is new,
    what is fixed, and what they should do differently because of it.

    When the release body cites a pull request, an issue, a discussion,
    a blog post, or a doc page, use the `fetch_url_content` tool to read
    the linked page. The release body usually only names changes; the
    linked pages explain them. Fetch every link that looks substantive
    before you write, then ground each bullet in what those pages
    actually say. Do not invent context that isn't in either the
    release body or a page you fetched.

    Output rules:
    - Plain GitHub-flavoured markdown. Headings only if there are
      multiple themes; otherwise a short paragraph plus a bulleted
      list.
    - Group related changes. Drop noise (dependency bumps, CI changes,
      doc-only PRs) unless they are user-visible.
    - Speak to the reader directly: "you can now…", "this version
      improves…". Avoid passive voice like "was added".
    - No author handles, no PR numbers, no commit hashes, no GitHub
      URLs, no labels like "feat:", "fix:", "chore:".
    - Keep the whole body under ~250 words even if the source is long.
    - If the source body is empty, missing, or auto-generated boilerplate
      with no substance, output a single sentence summarising the tag
      from the meadow's perspective.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: [FetchUrlContent]

  operation(:rewrite_release,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Read the release body. Use the `fetch_url_content` tool to read any
    issues, pull requests, or other linked pages it cites so you can
    describe what those changes actually deliver. Then write a
    user-facing markdown changelog entry for `body`, grouped by theme
    when there are multiple changes. Follow every rule in the system
    prompt.
    """
  )
end
