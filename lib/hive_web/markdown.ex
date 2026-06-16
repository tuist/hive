defmodule HiveWeb.Markdown do
  @moduledoc false

  import Phoenix.HTML

  @paragraph_wrap ~r/\A<p>(.*)<\/p>\z/s
  @tag_split ~r/(<[^>]+>)/
  @mention ~r/(^|[^A-Za-z0-9_\/])@([A-Za-z0-9](?:[A-Za-z0-9._-]{0,37}[A-Za-z0-9])?)/u
  @mention_skip_tags ~w(a code pre)

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
    |> highlight_mentions()
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
    |> highlight_mentions()
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

  defp highlight_mentions(html) do
    @tag_split
    |> Regex.split(html, include_captures: true, trim: false)
    |> Enum.map_reduce([], &highlight_mentions_part/2)
    |> elem(0)
    |> Enum.join()
  end

  defp highlight_mentions_part("<" <> _rest = tag, skip_stack) do
    {tag, update_mention_skip_stack(skip_stack, tag)}
  end

  defp highlight_mentions_part(text, []), do: {highlight_mentions_text(text), []}
  defp highlight_mentions_part(text, skip_stack), do: {text, skip_stack}

  defp highlight_mentions_text(text) do
    Regex.replace(@mention, text, fn _match, prefix, handle ->
      mention = "@#{handle}"

      ~s(#{prefix}<span data-part="mention" data-mention="#{mention}">#{mention}</span>)
    end)
  end

  defp update_mention_skip_stack(skip_stack, tag) do
    cond do
      closing_tag = closing_tag_name(tag) ->
        List.delete(skip_stack, closing_tag)

      opening_tag = opening_tag_name(tag) ->
        if opening_tag in @mention_skip_tags and not self_closing_tag?(tag) do
          [opening_tag | skip_stack]
        else
          skip_stack
        end

      true ->
        skip_stack
    end
  end

  defp opening_tag_name(tag) do
    case Regex.run(~r/^<\s*([a-zA-Z0-9]+)/, tag, capture: :all_but_first) do
      [name] -> String.downcase(name)
      _ -> nil
    end
  end

  defp closing_tag_name(tag) do
    case Regex.run(~r/^<\s*\/\s*([a-zA-Z0-9]+)/, tag, capture: :all_but_first) do
      [name] -> String.downcase(name)
      _ -> nil
    end
  end

  defp self_closing_tag?(tag), do: String.match?(tag, ~r/\/\s*>\z/)
end
