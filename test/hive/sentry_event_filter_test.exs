defmodule Hive.SentryEventFilterTest do
  use ExUnit.Case, async: true

  describe "before_send/1" do
    test "drops ignored exception payloads" do
      event = event(exception: [%{type: "Phoenix.Router.NoRouteError"}])

      assert Hive.SentryEventFilter.before_send(event) == false
    end

    test "keeps actionable exception payloads" do
      event = event(exception: [%{type: "RuntimeError"}])

      assert Hive.SentryEventFilter.before_send(event) == event
    end
  end

  defp event(attrs) do
    struct!(
      Sentry.Event,
      Keyword.merge(
        [
          event_id: String.duplicate("0", 32),
          timestamp: 0
        ],
        attrs
      )
    )
  end
end
