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

    test "drops low-level database connection retry logs" do
      event =
        event(
          original_exception:
            DBConnection.ConnectionError.exception(
              "tcp connect (hive-postgres-rw:5432): connection refused - :econnrefused"
            ),
          source: :logger
        )

      assert Hive.SentryEventFilter.before_send(event) == false
    end

    test "keeps database connection errors captured outside logger retry loops" do
      event =
        event(
          original_exception:
            DBConnection.ConnectionError.exception(
              "tcp connect (hive-postgres-rw:5432): connection refused - :econnrefused"
            ),
          source: :plug
        )

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
