defmodule Hive.Drops.RssTest do
  use ExUnit.Case, async: true

  alias Hive.Drops.Rss

  describe "parse/1 with Atom 1.0" do
    test "extracts entries with id, title, link, summary, published" do
      xml = ~S"""
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Example</title>
        <entry>
          <id>urn:example:1</id>
          <title>First release</title>
          <link href="https://example.com/1" />
          <summary>Initial body</summary>
          <published>2026-06-18T10:00:00Z</published>
        </entry>
        <entry>
          <id>urn:example:2</id>
          <title>Second release</title>
          <link href="https://example.com/2" />
          <updated>2026-06-19T10:00:00Z</updated>
        </entry>
      </feed>
      """

      assert {:ok, [first, second]} = Rss.parse(xml)
      assert first.external_id == "urn:example:1"
      assert first.title == "First release"
      assert first.url == "https://example.com/1"
      assert first.body == "Initial body"
      assert first.published_at == ~U[2026-06-18 10:00:00Z]

      assert second.external_id == "urn:example:2"
      assert second.published_at == ~U[2026-06-19 10:00:00Z]
    end

    test "prefers alternate links as the entry permalink" do
      xml = ~S"""
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <id>urn:example:1</id>
          <title>Release notes</title>
          <link rel="self" href="https://example.com/feed/items/1" />
          <link rel="alternate" href="https://example.com/changelog/releases#release-notes" />
        </entry>
      </feed>
      """

      assert {:ok, [item]} = Rss.parse(xml)
      assert item.url == "https://example.com/changelog/releases#release-notes"
    end
  end

  describe "parse/1 with RSS 2.0" do
    test "extracts items with guid, title, link, description, pubDate" do
      xml = ~S"""
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Example feed</title>
          <item>
            <guid>https://example.com/posts/hello</guid>
            <title>Hello world</title>
            <link>https://example.com/posts/hello</link>
            <description>A new post about hello.</description>
            <pubDate>Tue, 10 Jun 2025 04:00:00 GMT</pubDate>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, [item]} = Rss.parse(xml)
      assert item.external_id == "https://example.com/posts/hello"
      assert item.title == "Hello world"
      assert item.url == "https://example.com/posts/hello"
      assert item.body == "A new post about hello."
      assert %DateTime{year: 2025, month: 6, day: 10} = item.published_at
    end

    test "derives a stable guid when none is present" do
      xml = ~S"""
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>Untagged post</title>
            <description>Body content.</description>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, [item]} = Rss.parse(xml)
      assert is_binary(item.external_id)
      assert String.length(item.external_id) > 0
    end
  end

  test "parse/1 returns error tuple on malformed XML" do
    assert {:error, _reason} = Rss.parse("<rss><channel>")
  end
end
