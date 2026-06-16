defmodule HiveWeb.Markdown do
  @moduledoc false

  import Phoenix.HTML

  @paragraph_wrap ~r/\A<p>(.*)<\/p>\z/s

  @options [
    extension: [
      strikethrough: true,
      tagfilter: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true,
      shortcodes: true,
      alerts: true
    ],
    parse: [smart: true, relaxed_autolinks: true],
    render: [unsafe: false, hardbreaks: false],
    syntax_highlight: [
      formatter:
        {:html_inline,
         theme: "github_light",
         pre_class: "hive-codeblock",
         italic: true,
         include_highlights: true}
    ],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  def render(markdown) when is_binary(markdown) do
    markdown
    |> MDEx.parse_document!(@options)
    |> MDEx.traverse_and_update(&downshift_heading/1)
    |> MDEx.to_html!(@options)
    |> raw()
  end

  def render(_markdown), do: raw("")

  @doc """
  Renders a single line of markdown as inline-only HTML, suitable for use
  inside an existing block element (issue titles, excerpts, badges). The
  outer `<p>` wrapper that MDEx adds for block rendering is stripped so
  the caller controls the surrounding element.
  """
  def inline(text) when is_binary(text) do
    text
    |> MDEx.to_html!(@options)
    |> strip_paragraph_wrap()
    |> raw()
  end

  def inline(_text), do: raw("")

  @doc """
  Strips Markdown formatting from `text` and returns a plain-text string,
  preserving the original whitespace. Useful for previews, OpenGraph
  descriptions, or anywhere a Markdown body needs to be flattened.

  Intraword underscores are preserved so identifiers like
  `Module.do_something/1` survive the strip.
  """
  def to_plain_text(text) when is_binary(text) do
    text
    |> String.replace(~r/```[\s\S]*?```/, " ")
    |> String.replace(~r/~~~[\s\S]*?~~~/, " ")
    |> String.replace(~r/!\[[^\]]*\]\([^)]*\)/, " ")
    |> String.replace(~r/\[([^\]]+)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/^[ \t]*>+ ?/m, "")
    |> String.replace(~r/^[ \t]*[#]{1,6}[ \t]+/m, "")
    |> String.replace(~r/^[ \t]*(?:[-*+]|\d+\.)[ \t]+/m, "")
    |> String.replace(~r/`+/, "")
    |> String.replace(~r/\*+|~~/, "")
  end

  def to_plain_text(_text), do: ""

  @doc """
  Builds a single-line plain-text preview of `text`, suitable for table
  cells or summary lines. Strips Markdown formatting, collapses runs of
  whitespace into a single space, and truncates to `limit` characters
  (default 180).
  """
  def preview(text, limit \\ 180)

  def preview(text, limit) when is_binary(text) and is_integer(limit) and limit > 0 do
    text
    |> to_plain_text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, limit)
  end

  def preview(_text, _limit), do: ""

  defp downshift_heading(%MDEx.Heading{level: level} = node),
    do: %{node | level: min(level + 1, 6)}

  defp downshift_heading(node), do: node

  defp strip_paragraph_wrap(html) do
    trimmed = String.trim(html)

    case Regex.run(@paragraph_wrap, trimmed, capture: :all_but_first) do
      [inner] -> inner
      _ -> trimmed
    end
  end
end
