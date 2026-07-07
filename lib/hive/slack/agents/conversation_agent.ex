defmodule Hive.Slack.Agents.ConversationAgent do
  @moduledoc """
  Condukt agent that replies in a Slack thread when Hive's bot is
  @-mentioned. The agent receives the thread context and the mention text
  and returns a short reply that gets posted via `chat.postMessage`.
  """

  use Condukt

  alias Hive.Agents.StyleGuide
  alias Hive.Agents.Tools.CreateForageItem

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

  @github_label_schema %{
    type: "object",
    properties: %{
      name: %{type: "string"},
      description: %{type: "string"}
    },
    required: ["name"],
    additionalProperties: true
  }

  @input_schema %{
    type: "object",
    properties: %{
      mention_text: %{type: "string"},
      thread: %{type: "array", items: @message_schema},
      can_create_forage_item: %{type: "boolean"},
      available_github_labels: %{type: "array", items: @github_label_schema}
    },
    required: ["mention_text", "thread", "can_create_forage_item", "available_github_labels"],
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
    - If the user asks you to capture, create, file, or record a feature
      request, bug report, or feedback item, use `create_forage_item`
      when `can_create_forage_item` is true. Reply with the Hive link
      and the external link when the tool returns one.
    - If `available_github_labels` is not empty and you create a forage
      item, you may pass `github_labels` with up to three exact label
      names from that list. Choose only labels that clearly match the
      thread. Do not invent labels, and omit labels when none fit.
    - If `can_create_forage_item` is false and the user asks you to
      create a forage item, ask them to sign in to Hive and link their
      Slack profile before trying again.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: [CreateForageItem]

  def build_prompt(input) when is_map(input) do
    """
    Mention text:
    #{input["mention_text"] || ""}

    Can create forage item:
    #{input["can_create_forage_item"] == true}

    Available GitHub labels:
    #{format_github_labels(input["available_github_labels"] || [])}

    Thread messages, oldest first:
    #{format_thread(input["thread"] || [])}

    Reply as normal Slack message text. Do not wrap the reply in a structured object.
    """
  end

  operation(:reply_to_thread,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Read the mention text and the surrounding thread (in chronological
    order). Produce a single reply in the `reply` field.
    """
  )

  defp format_github_labels([]), do: "None"

  defp format_github_labels(labels) do
    Enum.map_join(labels, "\n", fn label ->
      name = Map.get(label, "name") || Map.get(label, :name) || ""
      description = Map.get(label, "description") || Map.get(label, :description)

      case description do
        description when is_binary(description) and description != "" ->
          "- #{name}: #{description}"

        _ ->
          "- #{name}"
      end
    end)
  end

  defp format_thread([]), do: "No prior messages."

  defp format_thread(messages) do
    Enum.map_join(messages, "\n", fn message ->
      user = Map.get(message, "user") || Map.get(message, :user) || "unknown"
      ts = Map.get(message, "ts") || Map.get(message, :ts) || "unknown time"
      text = Map.get(message, "text") || Map.get(message, :text) || ""

      "- #{ts} #{user}: #{text}"
    end)
  end
end
