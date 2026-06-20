defmodule HiveWeb.FeedXML do
  @moduledoc false

  def tag(name, value) when is_binary(value),
    do: ["<", name, ">", escape(value), "</", name, ">\n"]

  def tag(name, value), do: tag(name, to_string(value))

  def maybe_tag(_name, nil), do: []
  def maybe_tag(_name, ""), do: []
  def maybe_tag(name, value), do: tag(name, value)

  def escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  def escape(text), do: text |> to_string() |> escape()
end
