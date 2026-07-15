defmodule Hive.Slack.Unfurl.BlockKitTest do
  use ExUnit.Case, async: true

  alias Hive.Slack.Unfurl.BlockKit

  test "builds Block Kit payloads from generic metadata" do
    uri = URI.parse("https://hive.tuist.dev/specs/1")

    assert {:ok, payload} =
             BlockKit.generic(uri, %{
               title: "Spec",
               description: "Use <tag> & >\n\n- Keep the list",
               highlights: ["Draft"],
               section_label: "Specs"
             })

    assert [
             %{"type" => "header", "text" => %{"text" => "Spec"}},
             %{
               "type" => "section",
               "text" => %{"text" => "Use &lt;tag&gt; &amp; &gt;\n\n- Keep the list"}
             },
             %{"type" => "section", "fields" => [%{"text" => "- Draft"}]},
             %{"type" => "context", "elements" => [%{"text" => "Specs / Hive"}]},
             %{"type" => "actions", "elements" => [%{"url" => "https://hive.tuist.dev/specs/1"}]}
           ] = payload["blocks"]
  end

  test "keeps header text within Slack's limit" do
    uri = URI.parse("https://hive.tuist.dev/specs/1")

    assert {:ok, payload} = BlockKit.generic(uri, %{title: String.duplicate("a", 160)})

    header = get_in(payload, ["blocks", Access.at(0), "text", "text"])

    assert String.length(header) == 150
    assert String.ends_with?(header, "...")
  end

  test "builds native markdown description blocks" do
    uri = URI.parse("https://hive.tuist.dev/specs/1")
    description = "**Proposal**\n\n- Keep standard Markdown"

    assert {:ok, payload} =
             BlockKit.generic(uri, %{
               title: "Spec",
               description: description,
               description_format: :markdown
             })

    assert %{"type" => "markdown", "text" => ^description} = Enum.at(payload["blocks"], 1)
  end
end
