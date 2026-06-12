defmodule HiveWeb.Markdown do
  @moduledoc false

  import Phoenix.HTML

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

  defp downshift_heading(%MDEx.Heading{level: level} = node),
    do: %{node | level: min(level + 1, 6)}

  defp downshift_heading(node), do: node

  defp strip_paragraph_wrap(html) do
    trimmed = String.trim(html)

    case Regex.run(~r/\A<p>(.*)<\/p>\z/s, trimmed, capture: :all_but_first) do
      [inner] -> inner
      _ -> trimmed
    end
  end
end
