defmodule HiveWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias HiveWeb.Markdown

  defp html(markdown) do
    markdown
    |> Markdown.render()
    |> Phoenix.HTML.safe_to_string()
  end

  test "renders safe HTTP links" do
    rendered = html("[Hive](https://hive.tuist.dev/specs/1)")

    assert rendered =~ ~s|href="https://hive.tuist.dev/specs/1"|
    assert rendered =~ ">Hive</a>"
  end

  test "strips javascript: URLs from links" do
    rendered = html("[Click](javascript:alert(1))")

    refute rendered =~ "javascript:"
    refute rendered =~ "alert(1)"
  end

  test "escapes raw HTML" do
    rendered = html(~S|<script>alert(1)</script>|)

    refute rendered =~ "<script>"
  end

  test "downshifts headings by one level so the spec body never emits an h1" do
    rendered = html("# Top\n\n## Nested")

    assert rendered =~ "<h2>Top</h2>"
    assert rendered =~ "<h3>Nested</h3>"
  end

  test "renders GitHub-style admonitions as classed callout divs" do
    rendered = html("> [!NOTE]\n> Heads up.\n\n> Plain quote.")

    assert rendered =~ ~s|class="markdown-alert markdown-alert-note"|
    assert rendered =~ "Heads up."
    assert rendered =~ "<blockquote>"
    assert rendered =~ "Plain quote."
  end

  test "highlights fenced code blocks" do
    rendered =
      html("""
      ```elixir
      defmodule Foo do
      end
      ```
      """)

    assert rendered =~ "hive-codeblock"
    assert rendered =~ "language-elixir"
    assert rendered =~ "defmodule"
  end
end
