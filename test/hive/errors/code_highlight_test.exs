defmodule Hive.Errors.CodeHighlightTest do
  use ExUnit.Case, async: true

  alias Hive.Errors.CodeHighlight

  defp frame(overrides \\ %{}) do
    Map.merge(
      %{
        "pre_context" => ["defmodule Foo do"],
        "context_line" => "  def bar(x), do: x + 1",
        "post_context" => ["end"],
        "lineno" => 63
      },
      overrides
    )
  end

  describe "highlight_frame/2" do
    test "emits themed token spans rather than falling back to plain text" do
      html = CodeHighlight.highlight_frame(frame(), "elixir")

      assert html =~ ~s(<pre class="lumis")
      assert html =~ ~s(class="language-elixir")

      # The fallback escapes source without tokenizing, so a colored span for
      # a keyword is what separates real highlighting from a silent fallback.
      assert html =~ ~r/<span style="color: #[0-9a-f]{6};">defmodule<\/span>/
    end

    test "numbers lines against the frame's position in the file" do
      html = CodeHighlight.highlight_frame(frame(), "elixir")

      assert html =~ ~s(data-line="62")
      assert html =~ ~s(data-line="63")
      assert html =~ ~s(data-line="64")
      refute html =~ ~s(data-line="1")
    end

    test "marks the failing context line" do
      html = CodeHighlight.highlight_frame(frame(), "elixir")

      assert html =~ ~r/<div class="l-line" style="[^"]+" data-line="63">/
    end

    test "leaves line numbers untouched when the frame starts at the first line" do
      html = CodeHighlight.highlight_frame(frame(%{"lineno" => 2}), "elixir")

      assert html =~ ~s(data-line="1")
      assert html =~ ~s(data-line="3")
    end

    test "renumbers without rewriting source text that looks like an attribute" do
      html =
        CodeHighlight.highlight_frame(
          frame(%{
            "pre_context" => [],
            "context_line" => ~s(x = "data-line=\\"99\\""),
            "post_context" => [],
            "lineno" => 50
          }),
          "elixir"
        )

      # Lumis escapes the quotes in the source, so the literal text can never
      # be mistaken for the real attribute and renumbered along with it.
      assert html =~ "&quot;data-line="
      assert [_only_one] = Regex.scan(~r/<div class="l-line"[^>]*data-line="(\d+)"/, html)
      assert html =~ ~s(data-line="50")
      refute html =~ ~s(data-line="148")
    end

    test "falls back to plain rendering for an unknown platform" do
      html = CodeHighlight.highlight_frame(frame(), "brainfuck")

      assert html =~ ~s(<pre class="lumis">)
      assert html =~ ~s(data-line="63")
      refute html =~ "<span style=\"color:"
    end

    test "returns nil when the frame carries no source context" do
      assert CodeHighlight.highlight_frame(
               %{"pre_context" => [], "context_line" => nil, "post_context" => []},
               "elixir"
             ) == nil

      assert CodeHighlight.highlight_frame("not a frame", "elixir") == nil
    end
  end
end
