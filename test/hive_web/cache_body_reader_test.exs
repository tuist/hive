defmodule HiveWeb.CacheBodyReaderTest do
  use ExUnit.Case, async: true

  alias HiveWeb.CacheBodyReader

  test "preserves Plug's too-large body signal" do
    conn = Plug.Test.conn(:post, "/webhooks/github", "too-large")

    assert {:more, "too", _conn} = CacheBodyReader.read_body(conn, length: 3, read_length: 3)
  end
end
