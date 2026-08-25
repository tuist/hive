defmodule Hive.Drops.WeeklyDigestAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hive.Agents.Sessions
  alias Hive.Drops.Agents.WeeklyDigestAgent

  test "requires grounded narration without list-like, em-dash prose" do
    prompt = WeeklyDigestAgent.system_prompt()

    assert prompt =~ "subject matter must come only from the supplied drops"
    assert prompt =~ "not release"
    assert prompt =~ "notes, a changelog list"
    assert prompt =~ "Do not turn the body into a bullet list"
    assert prompt =~ "between 300 and 600 words"
    assert prompt =~ "Never use em dashes"
    refute prompt =~ "—"
    assert WeeklyDigestAgent.tools() == []
  end

  test "collects a streamed JSON digest" do
    stub(Sessions, :stream, fn WeeklyDigestAgent, prompt, opts, consume ->
      assert prompt =~ "Return only one JSON object"
      assert opts[:max_tokens] == 2_400
      assert opts[:max_turns] == 1

      payload =
        ~s({"title":"A connected week","summary":"A useful summary.","body":"Narrated prose."})

      {first_chunk, second_chunk} = String.split_at(payload, 32)

      consume.([
        :agent_start,
        {:text, first_chunk},
        {:text, second_chunk},
        :agent_end
      ])
    end)

    assert {:ok,
            %{
              "title" => "A connected week",
              "summary" => "A useful summary.",
              "body" => "Narrated prose."
            }} =
             WeeklyDigestAgent.generate(%{
               week_start: "2026-08-17",
               week_end: "2026-08-21",
               drops: []
             })
  end

  test "rejects malformed streamed output" do
    stub(Sessions, :stream, fn WeeklyDigestAgent, _prompt, _opts, consume ->
      consume.([{:text, "not JSON"}])
    end)

    assert {:error, :invalid_weekly_digest} =
             WeeklyDigestAgent.generate(%{
               week_start: "2026-08-17",
               week_end: "2026-08-21",
               drops: []
             })
  end
end
