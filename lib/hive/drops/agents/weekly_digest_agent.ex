defmodule Hive.Drops.Agents.WeeklyDigestAgent do
  @moduledoc """
  Condukt agent that connects a completed week of public drops into a
  single narrated edition.
  """

  use Condukt

  alias Hive.Agents.Sessions
  alias Hive.Agents.StyleGuide

  @max_tokens 2_400

  @impl true
  def system_prompt do
    """
    You write Hive's weekly Drops digest as an editorial narration of what
    shipped, not release notes, a changelog list, or marketing copy. The
    subject matter must come only from the supplied drops.

    Voice and structure:
    - Begin with a concrete observation about the week and name the
      thread connecting the most meaningful changes.
    - Build a point of view. Explain why the changes matter together,
      where the work is heading, or what product belief they reveal.
    - Prefer direct sentences, concrete nouns, and natural transitions.
      First person is welcome when it strengthens the narration.
    - Vary paragraph length. A short standalone sentence can carry an
      important turn.
    - End with a grounded implication or open direction, not a generic
      recap, celebration, or call to action.
    - Use Markdown with paragraphs and, only when useful, short level-two
      headings. Do not turn the body into a bullet list.
    - Link concrete claims to the matching Hive drop URL. Mention the
      strongest changes and connect them instead of forcing every input
      into the prose.
    - Keep the title specific and restrained. Keep the summary to one or
      two sentences. Keep the body between 300 and 600 words when the
      source material supports it, and stay shorter for a quiet week.
    - Never invent outcomes, metrics, motivations, or chronology.

    #{StyleGuide.prose_rules()}
    """
  end

  @impl true
  def tools, do: []

  def generate(input, opts \\ []) when is_map(input) and is_list(opts) do
    opts =
      opts
      |> Keyword.put_new(:max_tokens, @max_tokens)
      |> Keyword.put_new(:max_turns, 1)

    case Sessions.stream(__MODULE__, prompt(input), opts, &collect_text/1) do
      {:ok, response} -> decode_output(response)
      error -> error
    end
  end

  defp prompt(input) do
    """
    Write one cohesive weekly digest from the supplied public drops.

    Return only one JSON object, with exactly these string fields:
    - title: a specific, restrained title no longer than 160 characters
    - summary: one or two sentences no longer than 400 characters
    - body: 300 to 600 words of connected Markdown prose

    The body must be editorial narration, not a changelog list. Explain the
    thread between the strongest changes, link concrete claims using supplied
    Hive drop URLs, and do not mention the writing process. Do not use a code
    fence.

    #{Jason.encode!(input)}
    """
  end

  defp collect_text(events) do
    events
    |> Enum.reduce_while({:ok, []}, fn
      {:text, chunk}, {:ok, chunks} -> {:cont, {:ok, [chunk | chunks]}}
      {:error, reason}, _result -> {:halt, {:error, reason}}
      _event, result -> {:cont, result}
    end)
    |> case do
      {:ok, chunks} -> {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
      error -> error
    end
  end

  defp decode_output(response) do
    case Jason.decode(response) do
      {:ok, output} when is_map(output) -> {:ok, output}
      _other -> {:error, :invalid_weekly_digest}
    end
  end
end
