defmodule Hive.Errors.CodeHighlight do
  @moduledoc """
  Renders a Sentry stack-trace frame's source-context block as
  syntax-highlighted HTML. Uses [Lumis](https://hexdocs.pm/lumis) with
  the `catppuccin_latte` theme so colors stay legible on a light
  background.

  Callers hand in a frame map and get back HTML with:
    * every source line wrapped in a `.l-line` div
    * the failing `context_line` visually highlighted
    * fallback to plain-text rendering when no lexer matches the
      frame's `platform` (or when Lumis raises for any reason)
  """

  @default_theme "catppuccin_latte"

  @doc """
  Renders the source-context block for a frame as HTML.

  `platform` is the Sentry SDK platform identifier from the event
  (`"elixir"`, `"javascript"`, ...) and drives lexer selection.
  Returns `nil` when the frame carries no source context at all so
  callers can skip the whole `<pre>` block.
  """
  def highlight_frame(frame, platform) when is_map(frame) do
    pre = list(frame["pre_context"])
    ctx = frame["context_line"]
    post = list(frame["post_context"])

    cond do
      ctx == nil and pre == [] and post == [] ->
        nil

      true ->
        source = build_source(pre, ctx, post)
        base_line = frame["lineno"] || max(length(pre) + 1, 1)
        start_line = base_line - length(pre)
        current_line = length(pre) + 1

        case do_highlight(source, language_for(platform), start_line, current_line) do
          {:ok, html} -> html
          :error -> plain_html(source, start_line, current_line)
        end
    end
  end

  def highlight_frame(_, _), do: nil

  defp build_source(pre, ctx, post) do
    (pre ++ [ctx || ""] ++ post)
    |> Enum.map(&normalize_line/1)
    |> Enum.join("\n")
  end

  defp normalize_line(nil), do: ""
  defp normalize_line(line) when is_binary(line), do: line
  defp normalize_line(other), do: to_string(other)

  defp do_highlight(source, language, start_line, current_line) when is_binary(language) do
    Lumis.highlight(source,
      formatter:
        {:html_inline,
         language: language,
         theme: @default_theme,
         highlight_lines: %{lines: [current_line]},
         header: %{line_numbers: true, line_numbers_start: start_line}}
    )
    |> case do
      {:ok, html} -> {:ok, html}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp do_highlight(_source, _language = nil, _start, _current), do: :error

  # Fallback when Lumis has no lexer for the platform or raises.
  # Emits a compatible `<pre class="lumis">` structure so the same
  # CSS overrides apply.
  defp plain_html(source, start_line, current_line) do
    lines = String.split(source, "\n")

    line_htmls =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join("", fn {line, idx} ->
        highlight? = idx == current_line
        line_number = start_line + idx - 1
        escaped = line |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        style = if highlight?, do: ~s( style="background-color: #e9ebf2;"), else: ""

        ~s(<div class="l-line"#{style} data-line="#{line_number}">#{escaped}</div>)
      end)

    ~s(<pre class="lumis"><code translate="no" tabindex="0">#{line_htmls}</code></pre>)
  end

  # Sentry uses a stable set of platform identifiers. Map each to a
  # Lumis lexer name; unknown platforms return `nil` so we render as
  # plain text.
  defp language_for("elixir"), do: "elixir"
  defp language_for("erlang"), do: "erlang"
  defp language_for("javascript"), do: "javascript"
  defp language_for("node"), do: "javascript"
  defp language_for("typescript"), do: "typescript"
  defp language_for("python"), do: "python"
  defp language_for("ruby"), do: "ruby"
  defp language_for("go"), do: "go"
  defp language_for("java"), do: "java"
  defp language_for("csharp"), do: "csharp"
  defp language_for("php"), do: "php"
  defp language_for("perl"), do: "perl"
  defp language_for("rust"), do: "rust"
  defp language_for("swift"), do: "swift"
  defp language_for("kotlin"), do: "kotlin"
  defp language_for("dart"), do: "dart"
  defp language_for("scala"), do: "scala"
  defp language_for("clojure"), do: "clojure"
  defp language_for("haskell"), do: "haskell"
  defp language_for("cocoa"), do: "swift"
  defp language_for("objc"), do: "objective-c"
  defp language_for(_), do: nil

  defp list(l) when is_list(l), do: l
  defp list(_), do: []
end
