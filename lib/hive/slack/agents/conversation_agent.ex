defmodule Hive.Slack.Agents.ConversationAgent do
  @moduledoc """
  Condukt agent that replies in a Slack thread when Hive's bot is
  @-mentioned. The agent receives the thread context and the mention text
  and returns a short reply that gets posted via `chat.postMessage`.
  """

  use Condukt

  alias Hive.Agents.StyleGuide
  alias Hive.Agents.Tools.CreateForageItem
  alias Hive.Agents.Tools.ListGitHubLabels

  @message_schema %{
    type: "object",
    properties: %{
      user: %{type: "string"},
      text: %{type: "string"},
      ts: %{type: "string"},
      triggering_mention: %{type: "boolean"}
    },
    required: ["text"],
    additionalProperties: true
  }

  @input_schema %{
    type: "object",
    properties: %{
      thread: %{type: "array", items: @message_schema},
      omitted_thread_messages: %{type: "integer"},
      can_create_forage_item: %{type: "boolean"},
      slack_profile_link: %{type: "string", minLength: 1}
    },
    required: [
      "thread",
      "omitted_thread_messages",
      "can_create_forage_item",
      "slack_profile_link"
    ],
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
    - The thread marks the message that triggered this run. Answer that
      mention, using the other messages only as context.
    - If the user asks you to capture, create, file, or record a feature
      request, bug report, or feedback item, use `create_forage_item`
      when `can_create_forage_item` is true. Reply with the Hive link
      and the external link when the tool returns one.
    - Before calling `create_forage_item`, remove sensitive and identifying
      information from the title and description. Never include who
      requested the item or who is affected. Omit people's names, Slack
      handles and user identifiers, email addresses, customer or account
      names, workspace or organization names, and private links. Preserve
      only the technical behavior, generalized impact, and context needed
      to act on the item.
    - Omit `source_url` when it is a private Slack or internal link.
    - When matching GitHub labels would help a forage item, call
      `list_github_labels` first. You may pass `github_labels` with up to
      three exact names returned by that tool. Do not invent labels, and
      omit labels when none fit.
    - If `can_create_forage_item` is false and the user asks you to
      create a forage item, do not call any tools. Ask them to connect
      their Slack profile before trying again and include the exact
      Slack-formatted link from `Slack profile connection link`.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: [ListGitHubLabels, CreateForageItem]

  def build_prompt(input) when is_map(input) do
    """
    Can create forage item:
    #{input["can_create_forage_item"] == true}

    Slack profile connection link:
    <#{input["slack_profile_link"]}|Connect your Slack profile>

    Thread messages, oldest first:
    #{format_thread(input["thread"] || [])}

    Earlier messages omitted because the thread exceeded the context budget:
    #{input["omitted_thread_messages"] || 0}

    Reply as normal Slack message text. Do not wrap the reply in a structured object.
    """
  end

  operation(:reply_to_thread,
    input: @input_schema,
    output: @output_schema,
    instructions: """
    Read the triggering mention and the surrounding thread in chronological
    order. Produce a single reply in the `reply` field.
    """
  )

  defp format_thread([]), do: "No prior messages."

  defp format_thread(messages) do
    Enum.map_join(messages, "\n", fn message ->
      user = Map.get(message, "user") || Map.get(message, :user) || "unknown"
      ts = Map.get(message, "ts") || Map.get(message, :ts) || "unknown time"
      text = Map.get(message, "text") || Map.get(message, :text) || ""

      triggering? =
        Map.get(message, "triggering_mention") || Map.get(message, :triggering_mention)

      marker = if triggering?, do: " [triggering mention]", else: ""

      "-#{marker} #{ts} #{user}: #{text}"
    end)
  end
end
