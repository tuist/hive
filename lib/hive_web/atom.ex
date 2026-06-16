defmodule HiveWeb.Atom do
  @moduledoc """
  Minimal Atom 1.0 feed renderer.

  Takes a feed map and produces an XML document suitable for serving from
  `*/atom.xml` endpoints. Feed and entry maps follow this shape:

      %{
        id: String.t(),
        title: String.t(),
        subtitle: String.t() | nil,
        updated: DateTime.t(),
        self_url: String.t(),
        alternate_url: String.t(),
        entries: [entry]
      }

      entry: %{
        id: String.t(),
        title: String.t(),
        updated: DateTime.t(),
        url: String.t(),
        summary: String.t() | nil,
        author_name: String.t() | nil,
        author_email: String.t() | nil
      }
  """

  @doc "Renders the feed as an Atom 1.0 XML binary."
  def render(feed) when is_map(feed) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<feed xmlns="http://www.w3.org/2005/Atom">\n),
      tag("title", feed.title),
      maybe_tag("subtitle", feed[:subtitle]),
      ~s(<link rel="self" type="application/atom+xml" href="),
      escape(feed.self_url),
      ~s("/>\n),
      ~s(<link rel="alternate" type="text/html" href="),
      escape(feed.alternate_url),
      ~s("/>\n),
      tag("id", feed.id),
      tag("updated", iso8601(feed.updated)),
      Enum.map(feed.entries, &entry/1),
      ~s(</feed>\n)
    ]
    |> IO.iodata_to_binary()
  end

  defp entry(entry) do
    [
      "<entry>\n",
      tag("id", entry.id),
      tag("title", entry.title),
      tag("updated", iso8601(entry.updated)),
      ~s(<link rel="alternate" type="text/html" href="),
      escape(entry.url),
      ~s("/>\n),
      author(entry),
      maybe_tag("summary", entry[:summary]),
      "</entry>\n"
    ]
  end

  defp author(%{author_name: name} = entry) when is_binary(name) and name != "" do
    [
      "<author>\n",
      tag("name", name),
      maybe_tag("email", entry[:author_email]),
      "</author>\n"
    ]
  end

  defp author(_entry), do: []

  defp tag(name, value) when is_binary(value),
    do: ["<", name, ">", escape(value), "</", name, ">\n"]

  defp tag(name, value), do: tag(name, to_string(value))

  defp maybe_tag(_name, nil), do: []
  defp maybe_tag(_name, ""), do: []
  defp maybe_tag(name, value), do: tag(name, value)

  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp iso8601(%NaiveDateTime{} = ndt),
    do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape(text), do: text |> to_string() |> escape()
end
