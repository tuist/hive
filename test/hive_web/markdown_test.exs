defmodule HiveWeb.MarkdownTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

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

  test "strips inline event handlers from img tags" do
    rendered = html(~S|<img src=x onerror="alert(1)">|)

    refute rendered =~ "onerror"
    refute rendered =~ "alert(1)"
  end

  test "escapes HTML-special characters in plain text" do
    rendered = html("1 < 2 && 3 > 2")

    refute rendered =~ "<2"
    refute rendered =~ "&&"
    assert rendered =~ "&lt;"
    assert rendered =~ "&gt;"
    assert rendered =~ "&amp;"
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

  test "renders GitHub-style admonitions with the Noora alert component" do
    rendered =
      render_component(&Markdown.content/1, %{
        id: "incident-body",
        body: "> [!IMPORTANT]\n> Prevention work is still in progress."
      })

    assert rendered =~ ~s(class="noora-alert")
    assert rendered =~ ~s(data-status="information")
    assert rendered =~ ~s(data-type="secondary")
    assert rendered =~ ~s(data-size="large")
    assert rendered =~ "Important"
    assert rendered =~ "Prevention work is still in progress."
    refute rendered =~ "markdown-alert"
  end

  test "maps every GitHub-style admonition to a Noora alert status" do
    admonitions = [
      {"NOTE", "information"},
      {"TIP", "success"},
      {"WARNING", "warning"},
      {"CAUTION", "error"}
    ]

    for {type, status} <- admonitions do
      rendered =
        render_component(&Markdown.content/1, %{
          id: "#{String.downcase(type)}-body",
          body: "> [!#{type}]\n> #{String.capitalize(type)} content."
        })

      assert rendered =~ ~s(class="noora-alert")
      assert rendered =~ ~s(data-status="#{status}")
      assert rendered =~ String.capitalize(type)
      refute rendered =~ "markdown-alert"
    end
  end

  test "renders Markdown tables with the Noora table component" do
    rendered =
      render_component(&Markdown.content/1, %{
        id: "incident-body",
        body:
          "| Mitigation | Evidence |\n| --- | --- |\n| Remove legacy writer | Pull request 12192 |"
      })

    assert rendered =~ ~s(id="incident-body-table-1")
    assert rendered =~ ~s(class="noora-table")
    assert rendered =~ "Mitigation"
    assert rendered =~ "Evidence"
    assert rendered =~ "Remove legacy writer"
    assert rendered =~ "Pull request 12192"
  end

  test "renders mentions as tag spans" do
    rendered = html("@marek thanks for the pass.")

    assert rendered =~ ~s|<span data-part="mention" data-mention="@marek">@marek</span>|
  end

  test "does not render emails, code, or link text as mentions" do
    rendered = html("pedro@tuist.dev `@raw` [@link](https://example.com/@link) @marek")

    refute rendered =~ ~s|data-mention="@tuist"|
    refute rendered =~ ~s|data-mention="@raw"|
    refute rendered =~ ~s|data-mention="@link"|
    assert rendered =~ ~s|<span data-part="mention" data-mention="@marek">@marek</span>|
  end

  describe "render_markup/2" do
    test "renders sanitized feed markup" do
      rendered =
        "<p>Use <strong>trusted cache uploads</strong>.</p><script>alert(1)</script>"
        |> Markdown.render_markup()
        |> Phoenix.HTML.safe_to_string()

      assert rendered =~ "<p>Use <strong>trusted cache uploads</strong>.</p>"
      refute rendered =~ "<script>"
      refute rendered =~ "alert(1)"
    end

    test "absolutizes relative links and images from a source URL" do
      rendered =
        ~S|<p><a href="/docs/cache">Docs</a><img src="../images/cache.png" alt="Cache"></p>|
        |> Markdown.render_markup(base_url: "https://tuist.dev/changelog/cache-upload")
        |> Phoenix.HTML.safe_to_string()

      assert rendered =~ ~s|href="https://tuist.dev/docs/cache"|
      assert rendered =~ ~s|src="https://tuist.dev/images/cache.png"|
    end
  end

  defp inline(markdown) do
    markdown
    |> Markdown.inline()
    |> Phoenix.HTML.safe_to_string()
  end

  describe "inline/1" do
    test "renders inline code spans without a wrapping paragraph" do
      rendered = inline("Static framework with `.metal` produces `default.metallib`")

      assert rendered ==
               "Static framework with <code>.metal</code> produces <code>default.metallib</code>"
    end

    test "escapes raw HTML in inline input" do
      rendered = inline(~S|<script>alert(1)</script>|)

      refute rendered =~ "<script>"
    end

    test "returns an empty safe string for nil" do
      assert Phoenix.HTML.safe_to_string(Markdown.inline(nil)) == ""
    end
  end

  describe "to_plain_text/1" do
    test "strips headings, fenced code, list markers, links, and emphasis" do
      body = """
      ## Why

      Tuist already runs `Tuist.Namespace.create_instance_with_ssh_connection/1`.

      - one
      - two

      See [docs](https://example.com) and **bold** and ~~strike~~.

      ```elixir
      def hidden, do: :ok
      ```
      """

      plain = Markdown.to_plain_text(body)

      refute plain =~ "##"
      refute plain =~ "```"
      refute plain =~ "**"
      refute plain =~ "~~"
      refute plain =~ "- one"
      assert plain =~ "Why"
      assert plain =~ "Tuist.Namespace.create_instance_with_ssh_connection/1"
      assert plain =~ "docs"
      refute plain =~ "https://example.com"
      assert plain =~ "bold"
      assert plain =~ "strike"
      refute plain =~ "def hidden"
    end

    test "strips markup imported from feeds" do
      body = """
      <p>Teams can switch to <strong>CI and account tokens only</strong>.</p>
      <img src="/cache.png" alt="Cache upload controls">
      """

      plain = Markdown.to_plain_text(body)

      refute plain =~ "<p>"
      refute plain =~ "<strong>"
      assert plain =~ "Teams can switch to CI and account tokens only."
      assert plain =~ "Cache upload controls"
    end

    test "returns an empty string for nil" do
      assert Markdown.to_plain_text(nil) == ""
    end
  end

  describe "preview/2" do
    test "collapses whitespace and truncates to the given limit" do
      assert Markdown.preview("## Hello\n\nthere\nworld", 100) == "Hello there world"
    end

    test "uses 180 characters by default" do
      body = String.duplicate("a", 300)
      assert String.length(Markdown.preview(body)) == 180
    end

    test "returns an empty string for nil" do
      assert Markdown.preview(nil) == ""
    end
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
