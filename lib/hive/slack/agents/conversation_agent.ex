defmodule Hive.Slack.Agents.ConversationAgent do
  @moduledoc """
  Condukt agent that replies in a Slack thread when Hive's bot is
  @-mentioned. The agent receives the thread context and the mention text
  and returns a short reply that gets posted via `chat.postMessage`.
  """

  use Condukt

  alias Hive.Agents.StyleGuide

  @message_schema %{
    type: "object",
    properties: %{
      user: %{type: "string"},
      text: %{type: "string"},
      ts: %{type: "string"}
    },
    required: ["text"],
    additionalProperties: true
  }

  @input_schema %{
    type: "object",
    properties: %{
      mention_text: %{type: "string"},
      thread: %{type: "array", items: @message_schema}
    },
    required: ["mention_text", "thread"],
    additionalProperties: false
  }

  @output_schema %{
    type: "object",
    properties: %{
      reply: %{type: "string", minLength: 1, maxLength: 3000}
    },
    required: ["reply"],
    additionalProperties: false
  }

  @impl true
  def system_prompt do
    """
    You answer in a Slack thread on behalf of Hive's assistant. The user
    has just @-mentioned the bot, and the thread context (if any) is the
    surrounding conversation in that channel.

    Rules:
    - Reply directly, with no preamble like "Sure" or "Of course".
    - Keep replies short: one or two paragraphs unless a list is clearly
      better. Slack threads are read inline, not as documents.
    - Format with Slack-flavored markdown: `*bold*`, `_italic_`,
      backticks for code, and angle-bracket links like `<https://example.com|label>`.
    - If you don't have enough information, ask one specific clarifying
      question instead of guessing.
    - Do not invent facts about Hive, the workspace, or its members.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  operation(:reply_to_thread,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Read the mention text and the surrounding thread (in chronological
    order). Produce a single reply in the `reply` field.
    """
  )
end
