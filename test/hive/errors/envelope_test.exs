defmodule Hive.Errors.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Hive.Errors.Envelope

  describe "parse/1" do
    test "parses a length-prefixed event item" do
      payload = ~s({"event_id":"abc","message":"hi"})

      body =
        [
          ~s({"event_id":"abc","sent_at":"2026-09-03T15:00:00Z"}),
          ~s({"type":"event","length":#{byte_size(payload)},"content_type":"application/json"}),
          payload
        ]
        |> Enum.join("\n")

      assert {:ok, envelope} = Envelope.parse(body)
      assert envelope.header["event_id"] == "abc"
      assert [item] = envelope.items
      assert item.type == "event"
      assert item.payload == payload
    end

    test "parses newline-delimited items when length is absent" do
      body =
        [
          ~s({"event_id":"abc"}),
          ~s({"type":"event"}),
          ~s({"level":"error"})
        ]
        |> Enum.join("\n")

      assert {:ok, envelope} = Envelope.parse(body)
      assert [item] = envelope.items
      assert item.payload == ~s({"level":"error"})
    end

    test "parses multiple items in sequence" do
      first_payload = ~s({"event_id":"abc"})
      second_payload = ~s({"transaction":"POST /widgets"})

      body =
        [
          ~s({}),
          ~s({"type":"event","length":#{byte_size(first_payload)}}),
          first_payload,
          ~s({"type":"transaction","length":#{byte_size(second_payload)}}),
          second_payload
        ]
        |> Enum.join("\n")

      assert {:ok, envelope} = Envelope.parse(body)
      assert Enum.map(envelope.items, & &1.type) == ["event", "transaction"]
    end

    test "rejects an unparseable envelope header" do
      assert {:error, :invalid_envelope} = Envelope.parse("not-json\n")
    end

    test "tolerates an empty envelope" do
      assert {:ok, %{items: []}} = Envelope.parse(~s({}))
    end
  end
end
