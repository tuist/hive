defmodule Hive.Errors.SentryEventTest do
  use ExUnit.Case, async: true

  alias Hive.Errors.SentryEvent

  describe "parse/1" do
    test "extracts the first exception's type, value, and frames" do
      event =
        SentryEvent.parse(%{
          "event_id" => "abcd1234abcd1234abcd1234abcd1234",
          "timestamp" => "2026-09-03T15:00:00Z",
          "platform" => "elixir",
          "exception" => %{
            "values" => [
              %{
                "type" => "RuntimeError",
                "value" => "boom",
                "stacktrace" => %{
                  "frames" => [
                    %{"function" => "outer/0", "in_app" => true},
                    %{"function" => "inner/0", "in_app" => true}
                  ]
                }
              }
            ]
          }
        })

      assert event.exception_type == "RuntimeError"
      assert event.exception_value == "boom"
      assert event.top_frame["function"] == "inner/0"
    end

    test "picks the last in-app frame as the top frame" do
      event =
        SentryEvent.parse(%{
          "exception" => %{
            "values" => [
              %{
                "type" => "Boom",
                "value" => "!",
                "stacktrace" => %{
                  "frames" => [
                    %{"function" => "vendor/0", "in_app" => false},
                    %{"function" => "app_a/0", "in_app" => true},
                    %{"function" => "app_b/0", "in_app" => true},
                    %{"function" => "vendor_wrapper/0", "in_app" => false}
                  ]
                }
              }
            ]
          }
        })

      assert event.top_frame["function"] == "app_b/0"
    end

    test "falls back to the last frame when nothing is in_app" do
      event =
        SentryEvent.parse(%{
          "exception" => %{
            "values" => [
              %{
                "type" => "Boom",
                "stacktrace" => %{
                  "frames" => [
                    %{"function" => "vendor_a/0", "in_app" => false},
                    %{"function" => "vendor_b/0", "in_app" => false}
                  ]
                }
              }
            ]
          }
        })

      assert event.top_frame["function"] == "vendor_b/0"
    end

    test "defaults missing scalar fields" do
      event = SentryEvent.parse(%{})

      assert event.platform == "other"
      assert event.level == "error"
      assert event.environment == "production"
      assert event.tags == %{}
      assert event.exception_type == nil
    end

    test "clamps unknown levels back to error" do
      event = SentryEvent.parse(%{"level" => "totally-invented"})
      assert event.level == "error"
    end

    test "reads a formatted logentry message when message is absent" do
      event = SentryEvent.parse(%{"logentry" => %{"formatted" => "hello world"}})
      assert event.message == "hello world"
    end

    test "extracts the sdk name and version" do
      event = SentryEvent.parse(%{"sdk" => %{"name" => "sentry.python", "version" => "1.2.3"}})
      assert event.sdk_name == "sentry.python"
      assert event.sdk_version == "1.2.3"
    end

    test "parses timestamps in ISO 8601 and unix seconds" do
      iso = SentryEvent.parse(%{"timestamp" => "2026-09-03T12:00:00Z"})
      unix = SentryEvent.parse(%{"timestamp" => 1_780_000_000.5})

      assert iso.timestamp.year == 2026
      assert %DateTime{} = unix.timestamp
    end

    test "interprets naive ISO 8601 timestamps as UTC" do
      event = SentryEvent.parse(%{"timestamp" => "2026-09-09T10:03:33.889513"})

      assert event.timestamp == ~U[2026-09-09 10:03:33.889513Z]
    end

    test "preserves the instant of offset-bearing timestamps" do
      event = SentryEvent.parse(%{"timestamp" => "2026-09-09T12:03:33.889513+02:00"})

      assert event.timestamp == ~U[2026-09-09 10:03:33.889513Z]
    end

    test "parses unix timestamps sent as numbers" do
      event = SentryEvent.parse(%{"timestamp" => 1_788_000_213.889513})

      assert event.timestamp == DateTime.from_unix!(1_788_000_213_889_513, :microsecond)
    end

    test "falls back to the ingest time for unparseable timestamps" do
      before = DateTime.utc_now()
      event = SentryEvent.parse(%{"timestamp" => "not a timestamp"})
      later = DateTime.utc_now()

      assert DateTime.compare(event.timestamp, before) != :lt
      assert DateTime.compare(event.timestamp, later) != :gt
    end

    test "honors explicit fingerprint override" do
      event = SentryEvent.parse(%{"fingerprint" => ["custom", "group"]})
      assert event.fingerprint_override == ["custom", "group"]
    end

    test "extracts the Rust SDK tracing event name from contexts" do
      event =
        SentryEvent.parse(%{
          "contexts" => %{
            "Rust Tracing Fields" => %{"name" => "BatchSpanProcessor.ExportError"}
          }
        })

      assert event.tracing_name == "BatchSpanProcessor.ExportError"

      assert SentryEvent.parse(%{"contexts" => %{"os" => %{"name" => "Linux"}}}).tracing_name ==
               nil

      assert SentryEvent.parse(%{}).tracing_name == nil
    end

    test "converts non-binary tag values to strings" do
      event = SentryEvent.parse(%{"tags" => %{"attempt" => 3, "ok" => true}})
      assert event.tags == %{"attempt" => "3", "ok" => "true"}
    end
  end

  describe "title/1" do
    test "combines exception type and value when both are present" do
      event =
        SentryEvent.parse(%{
          "exception" => %{"values" => [%{"type" => "ArgumentError", "value" => "bad"}]}
        })

      assert SentryEvent.title(event) == "ArgumentError: bad"
    end

    test "falls back to the message" do
      event = SentryEvent.parse(%{"message" => "connection refused"})
      assert SentryEvent.title(event) == "connection refused"
    end

    test "falls back to the tracing event name when there is no message" do
      event =
        SentryEvent.parse(%{
          "message" => "",
          "logger" => "opentelemetry_sdk",
          "contexts" => %{
            "Rust Tracing Fields" => %{"name" => "BatchSpanProcessor.ExportError"}
          }
        })

      assert SentryEvent.title(event) == "BatchSpanProcessor.ExportError"
    end

    test "falls back to the logger when there is no tracing event name" do
      event = SentryEvent.parse(%{"message" => "", "logger" => "opentelemetry_sdk"})
      assert SentryEvent.title(event) == "opentelemetry_sdk"
    end

    test "falls back to the event id when the event carries no identity" do
      event = SentryEvent.parse(%{"event_id" => "abcd1234abcd1234abcd1234abcd1234"})
      assert SentryEvent.title(event) == "Event abcd1234abcd1234abcd1234abcd1234"
    end
  end

  describe "culprit/1" do
    test "uses top frame function and location when available" do
      event =
        SentryEvent.parse(%{
          "exception" => %{
            "values" => [
              %{
                "type" => "Boom",
                "stacktrace" => %{
                  "frames" => [
                    %{
                      "function" => "MyModule.explode/1",
                      "filename" => "lib/my_module.ex",
                      "lineno" => 42,
                      "in_app" => true
                    }
                  ]
                }
              }
            ]
          }
        })

      assert SentryEvent.culprit(event) == "MyModule.explode/1 at lib/my_module.ex:42"
    end
  end
end
