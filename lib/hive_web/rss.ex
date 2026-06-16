defmodule HiveWeb.Rss do
  @moduledoc """
  Minimal RSS 2.0 feed renderer.

  Takes a feed map shaped like `HiveWeb.Atom`'s and produces an RSS 2.0
  XML document. Dates are formatted as RFC 822 strings as required by
  the RSS specification.

      %{
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

  @doc "Renders the feed as an RSS 2.0 XML binary."
  def render(feed) when is_map(feed) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n),
      "<channel>\n",
      tag("title", feed.title),
      tag("link", feed.alternate_url),
      tag("description", feed[:subtitle] || feed.title),
      ~s(<atom:link href="),
      escape(feed.self_url),
      ~s(" rel="self" type="application/rss+xml"/>\n),
      tag("lastBuildDate", rfc822(feed.updated)),
      Enum.map(feed.entries, &item/1),
      "</channel>\n",
      "</rss>\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp item(entry) do
    [
      "<item>\n",
      tag("title", entry.title),
      tag("link", entry.url),
      ~s(<guid isPermaLink="true">),
      escape(entry.url),
      "</guid>\n",
      tag("pubDate", rfc822(entry.updated)),
      maybe_tag("description", entry[:summary]),
      maybe_author(entry),
      "</item>\n"
    ]
  end

  defp maybe_author(%{author_email: email, author_name: name})
       when is_binary(email) and email != "" and is_binary(name) and name != "" do
    tag("author", "#{email} (#{name})")
  end

  defp maybe_author(%{author_email: email}) when is_binary(email) and email != "",
    do: tag("author", email)

  defp maybe_author(_entry), do: []

  defp tag(name, value) when is_binary(value),
    do: ["<", name, ">", escape(value), "</", name, ">\n"]

  defp tag(name, value), do: tag(name, to_string(value))

  defp maybe_tag(_name, nil), do: []
  defp maybe_tag(_name, ""), do: []
  defp maybe_tag(name, value), do: tag(name, value)

  defp rfc822(%DateTime{} = dt),
    do: dt |> DateTime.shift_zone!("Etc/UTC") |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

  defp rfc822(%NaiveDateTime{} = ndt),
    do: ndt |> DateTime.from_naive!("Etc/UTC") |> rfc822()

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
