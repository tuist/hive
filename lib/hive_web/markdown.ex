defmodule HiveWeb.Markdown do
  @moduledoc false

  import Phoenix.HTML

  @paragraph_wrap ~r/\A<p>(.*)<\/p>\z/s
  @tag_split ~r/(<[^>]+>)/
  @html_url_attr ~r/(\s(?:href|src)=["'])([^"']+)(["'])/i
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
  Renders sanitized markup imported from external feeds.
  """
  def render_markup(markup, opts \\ [])

  def render_markup(markup, opts) when is_binary(markup) do
    markup
    |> absolutize_html_urls(Keyword.get(opts, :base_url))
    |> MDEx.safe_html(escape: [content: false, curly_braces_in_code: true])
    |> highlight_mentions()
    |> raw()
  end

  def render_markup(_markup, _opts), do: raw("")

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
    |> decode_html_entities()
    |> strip_html()
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

  defp strip_html(text) do
    text
    |> strip_tag_contents("script")
    |> strip_tag_contents("style")
    |> strip_tag_contents("noscript")
    |> String.replace(~r/<li\b[^>]*>/i, "\n")
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(
      ~r/<\/(p|div|section|article|aside|header|footer|nav|tr|table|ul|ol|h[1-6]|li)>/i,
      "\n"
    )
    |> String.replace(~r/<img\b[^>]*\balt=(["'])(.*?)\1[^>]*>/i, " \\2 ")
    |> String.replace(~r/<\/?[A-Za-z][^>]*>/, "")
    |> String.replace(~r/<!--.*?-->/s, " ")
  end

  defp strip_tag_contents(text, tag) do
    Regex.replace(~r/<#{tag}\b[^>]*>.*?<\/#{tag}>/is, text, "")
  end

  defp absolutize_html_urls(html, base_url) when is_binary(base_url) and base_url != "" do
    base_uri = URI.parse(base_url)

    if base_uri.scheme in ["http", "https"] and is_binary(base_uri.host) do
      Regex.replace(@html_url_attr, html, fn _match, prefix, url, suffix ->
        prefix <> absolutize_url(url, base_uri) <> suffix
      end)
    else
      html
    end
  end

  defp absolutize_html_urls(html, _base_url), do: html

  defp absolutize_url("#" <> _rest = url, _base_uri), do: url

  defp absolutize_url(url, base_uri) do
    uri = URI.parse(url)

    cond do
      uri.scheme in ["http", "https", "mailto", "tel", "data"] ->
        url

      is_binary(uri.scheme) ->
        url

      true ->
        base_uri
        |> URI.merge(url)
        |> URI.to_string()
    end
  rescue
    URI.Error -> url
  end

  defp decode_html_entities(text) do
    text
    |> decode_numeric_entities(~r/&#(\d+);/, 10)
    |> decode_numeric_entities(~r/&#x([0-9a-fA-F]+);/, 16)
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&#x27;", "'")
    |> String.replace("&apos;", "'")
  end

  defp decode_numeric_entities(text, regex, base) do
    Regex.replace(regex, text, fn _match, codepoint ->
      codepoint
      |> String.to_integer(base)
      |> maybe_codepoint()
    end)
  end

  defp maybe_codepoint(codepoint) when codepoint in 0..0x10FFFF do
    <<codepoint::utf8>>
  rescue
    ArgumentError -> ""
  end

  defp maybe_codepoint(_codepoint), do: ""

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
