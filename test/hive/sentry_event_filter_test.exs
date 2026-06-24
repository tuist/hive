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

  describe "report_oban_error?/2" do
    test "skips retryable job failures before the final attempt" do
      refute Hive.SentryEventFilter.report_oban_error?(nil, %{attempt: 1, max_attempts: 3})
      refute Hive.SentryEventFilter.report_oban_error?(nil, %{attempt: 2, max_attempts: 3})
    end

    test "reports job failures once attempts are exhausted" do
      assert Hive.SentryEventFilter.report_oban_error?(nil, %{attempt: 3, max_attempts: 3})
    end

    test "keeps reporting when Oban attempt metadata is unavailable" do
      assert Hive.SentryEventFilter.report_oban_error?(nil, %{})
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
