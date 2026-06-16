defmodule Hive.MCP.Components.Prompts.WriteSpec do
  @moduledoc """
  MCP prompt that loads the Hive spec writing guide into the caller's
  context. Pull it before drafting a new spec so the result follows the
  house style on altitude, voice, structure, and the things reviewers
  consistently push on.
  """

  @behaviour EMCP.Prompt

  alias Hive.Specs.StyleGuide

  @impl EMCP.Prompt
  def name, do: "write_spec"

  @impl EMCP.Prompt
  def description do
    "House style for drafting a Hive spec. Pull before writing so the draft follows the altitude, voice, and structure conventions reviewers expect."
  end

  @impl EMCP.Prompt
  def arguments do
    [
      %{
        name: "topic",
        description:
          "Optional subject of the spec being drafted. Woven into the prompt lede so the model is primed before the guidelines load.",
        required: false
      }
    ]
  end

  @impl EMCP.Prompt
  def template(_conn, args) do
    topic = args["topic"]

    %{
      description: "Hive spec writing guide.",
      messages: [
        %{
          role: "user",
          content: %{type: "text", text: StyleGuide.write_spec_prompt(topic)}
        }
      ]
    }
  end
end
