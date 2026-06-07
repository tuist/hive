defmodule HiveWeb.Markdown do
  @moduledoc false

  import Phoenix.HTML

  def render(markdown) when is_binary(markdown) do
    markdown
    |> String.trim()
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.map_join(&block_to_html/1)
    |> raw()
  end

  def render(_markdown), do: raw("")

  defp block_to_html("# " <> heading), do: "<h2>#{inline(heading)}</h2>"
  defp block_to_html("## " <> heading), do: "<h3>#{inline(heading)}</h3>"
  defp block_to_html("### " <> heading), do: "<h4>#{inline(heading)}</h4>"

  defp block_to_html(block) do
    block
    |> String.split("\n", trim: true)
    |> Enum.chunk_by(&list_item?/1)
    |> Enum.map_join(&lines_to_html/1)
  end

  defp lines_to_html([line | _lines] = lines) do
    if list_item?(line) do
      "<ul>#{Enum.map_join(lines, &list_item_to_html/1)}</ul>"
    else
      "<p>#{inline(Enum.join(lines, "\n"))}</p>"
    end
  end

  defp list_item?(line), do: String.starts_with?(String.trim_leading(line), "- ")

  defp list_item_to_html(line) do
    item = line |> String.trim_leading() |> String.trim_leading("- ")
    "<li>#{inline(item)}</li>"
  end

  defp inline(text) do
    text
    |> escape()
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
    |> String.replace(~r/\*\*([^*]+)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*([^*]+)\*/, "<em>\\1</em>")
    |> link()
    |> String.replace("\n", "<br />")
  end

  defp link(text) do
    Regex.replace(~r/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/, text, fn _match, label, url ->
      ~s(<a href="#{url}" rel="noopener noreferrer" target="_blank">#{label}</a>)
    end)
  end

  defp escape(text) do
    text
    |> html_escape()
    |> safe_to_string()
  end
end
