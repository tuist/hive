defmodule Hive.Errors.FingerprintTest do
  use ExUnit.Case, async: true

  alias Hive.Errors.Fingerprint
  alias Hive.Errors.SentryEvent

  describe "compute/1" do
    test "two events with the same type + frame + message hash the same" do
      event = fn message ->
        SentryEvent.parse(%{
          "message" => message,
          "exception" => %{
            "values" => [
              %{
                "type" => "RuntimeError",
                "stacktrace" => %{
                  "frames" => [
                    %{"function" => "boom/0", "filename" => "lib/x.ex", "in_app" => true}
                  ]
                }
              }
            ]
          }
        })
      end

      assert Fingerprint.compute(event.("boom")) == Fingerprint.compute(event.("boom"))
    end

    test "numeric-only differences in the message do not split groups" do
      event = fn message ->
        SentryEvent.parse(%{
          "message" => message,
          "exception" => %{
            "values" => [
              %{
                "type" => "RuntimeError",
                "stacktrace" => %{
                  "frames" => [
                    %{"function" => "process/0", "in_app" => true}
                  ]
                }
              }
            ]
          }
        })
      end

      assert Fingerprint.compute(event.("failed to process user 12345")) ==
               Fingerprint.compute(event.("failed to process user 99999"))
    end

    test "different exception types split groups" do
      base = fn type ->
        SentryEvent.parse(%{
          "exception" => %{
            "values" => [
              %{
                "type" => type,
                "stacktrace" => %{
                  "frames" => [
                    %{"function" => "same/0", "in_app" => true}
                  ]
                }
              }
            ]
          }
        })
      end

      refute Fingerprint.compute(base.("A")) == Fingerprint.compute(base.("B"))
    end

    test "an explicit sdk-supplied fingerprint wins" do
      a =
        SentryEvent.parse(%{
          "fingerprint" => ["order-processor"],
          "exception" => %{"values" => [%{"type" => "OrderFailed"}]}
        })

      b =
        SentryEvent.parse(%{
          "fingerprint" => ["order-processor"],
          "message" => "different message entirely"
        })

      assert Fingerprint.compute(a) == Fingerprint.compute(b)

      assert Fingerprint.compute(a) ==
               Base.encode16(:crypto.hash(:sha256, "order-processor"), case: :lower)
    end

    test "a default token alone uses the same grouping as an absent or empty fingerprint" do
      for event <- [
            exception_event(),
            SentryEvent.parse(%{"message" => "boom"}),
            SentryEvent.parse(%{})
          ],
          fingerprint <- [[], ["{{ default }}"], ["{{default}}"], ["{{  default  }}"]] do
        parsed = SentryEvent.parse(Map.put(event.payload, "fingerprint", fingerprint))
        assert Fingerprint.compute(parsed) == Fingerprint.compute(event)
      end
    end

    test "a worker fingerprint with the default token separates unrelated exceptions" do
      events = [
        exception_event(),
        exception_event(%{"type" => "Postgrex.Error", "value" => "permission denied"}),
        exception_event(%{"type" => "Oban.PerformError", "value" => "download timeout"}),
        exception_event(%{"value" => "no match: {:error, :bad_crc}"}),
        exception_event(%{"value" => "no match: {:error, :internal_unzip_error}"})
      ]

      fingerprints =
        Enum.map(events, fn event ->
          Fingerprint.compute(%{
            event
            | fingerprint_override: ["BuildWorker", "{{ default }}"]
          })
        end)

      assert length(Enum.uniq(fingerprints)) == length(events)
    end

    test "default tokens retain stack frame grouping and message normalization" do
      event = %{exception_event() | fingerprint_override: ["BuildWorker", "{{ default }}"]}
      other_frame = %{event | top_frame: %{"function" => "OtherProcessor.process/1"}}

      refute Fingerprint.compute(event) == Fingerprint.compute(other_frame)

      assert Fingerprint.compute(%{event | exception_value: "failed for record 123"}) ==
               Fingerprint.compute(%{event | exception_value: "failed for record 456"})
    end

    test "custom components refine default grouping in their supplied order" do
      event = exception_event()
      hybrid = %{event | fingerprint_override: ["BuildWorker", "{{ default }}"]}
      other_worker = %{event | fingerprint_override: ["OtherWorker", "{{ default }}"]}
      reversed = %{event | fingerprint_override: ["{{ default }}", "BuildWorker"]}
      compact = %{event | fingerprint_override: ["BuildWorker", "{{default}}"]}

      refute Fingerprint.compute(hybrid) == Fingerprint.compute(event)
      refute Fingerprint.compute(hybrid) == Fingerprint.compute(other_worker)
      refute Fingerprint.compute(hybrid) == Fingerprint.compute(reversed)
      assert Fingerprint.compute(hybrid) == Fingerprint.compute(compact)
    end

    test "custom fingerprints without a default token retain their literal hashes" do
      event = exception_event()

      for fingerprint <- [
            ["BuildWorker", "zip-errors"],
            ["prefix {{ default }} suffix"],
            ["{{ unknown }}"]
          ] do
        custom = %{event | fingerprint_override: fingerprint}

        unrelated = %{
          custom
          | exception_type: "Postgrex.Error",
            exception_value: "permission denied"
        }

        expected = Base.encode16(:crypto.hash(:sha256, Enum.join(fingerprint, "|")), case: :lower)

        assert Fingerprint.compute(custom) == expected
        assert Fingerprint.compute(unrelated) == expected
      end
    end

    test "structureless events group by logger, transaction, level, and tracing name" do
      base = log_event()

      variants = [
        log_event(%{"logger" => "other_sdk"}),
        log_event(%{"transaction" => "export_spans"}),
        log_event(%{"level" => "warning"}),
        log_event(%{"contexts" => %{"Rust Tracing Fields" => %{"name" => "Other.Error"}}})
      ]

      fingerprints = Enum.map([base | variants], &Fingerprint.compute/1)
      assert length(Enum.uniq(fingerprints)) == length(fingerprints)
    end

    test "structureless events no longer collapse into the empty-component bucket" do
      empty_components = Base.encode16(:crypto.hash(:sha256, "|||"), case: :lower)

      refute Fingerprint.compute(log_event()) == empty_components
      refute Fingerprint.compute(SentryEvent.parse(%{})) == empty_components
    end

    test "per-event noise in a structureless event does not split groups" do
      a = log_event(%{"server_name" => "kura-a", "release" => "kura@0.41.1"})
      b = log_event(%{"server_name" => "kura-b", "release" => "kura@0.42.0"})

      assert Fingerprint.compute(a) == Fingerprint.compute(b)
    end

    test "record identifiers in a structureless transaction do not split groups" do
      a = log_event(%{"transaction" => "GET /users/12345"})
      b = log_event(%{"transaction" => "GET /users/99999"})

      assert Fingerprint.compute(a) == Fingerprint.compute(b)
      refute Fingerprint.compute(a) == Fingerprint.compute(log_event())
    end

    test "the identity fallback only applies when every exception component is blank" do
      typed = %{log_event() | exception_type: "ExportError"}

      refute Fingerprint.compute(typed) == Fingerprint.compute(log_event())

      assert Fingerprint.compute(typed) ==
               Fingerprint.compute(%{typed | logger: "unused", tracing_name: "unused"})
    end

    test "a default token expands to the identity fallback for structureless events" do
      event = log_event()
      with_token = %{event | fingerprint_override: ["{{ default }}"]}
      other = %{with_token | tracing_name: "Other.Error"}

      assert Fingerprint.compute(with_token) == Fingerprint.compute(event)
      refute Fingerprint.compute(with_token) == Fingerprint.compute(other)
    end

    test "returns a 64-character lowercase hex digest" do
      digest = Fingerprint.compute(SentryEvent.parse(%{}))
      assert String.length(digest) == 64
      assert digest == String.downcase(digest)
      assert digest =~ ~r/^[0-9a-f]+$/
    end
  end

  defp exception_event(attrs \\ %{}) do
    exception =
      Map.merge(
        %{
          "type" => "MatchError",
          "value" => "no match: {:error, :bad_eocd}",
          "stacktrace" => %{
            "frames" => [%{"function" => "BuildProcessor.process_zip/3", "in_app" => true}]
          }
        },
        attrs
      )

    SentryEvent.parse(%{"exception" => %{"values" => [exception]}})
  end

  # Mirrors the shape the Sentry Rust SDK sends for `tracing` events:
  # no exception, no frames, and an empty message.
  defp log_event(attrs \\ %{}) do
    %{
      "logger" => "opentelemetry_sdk",
      "level" => "error",
      "platform" => "native",
      "message" => "",
      "contexts" => %{
        "Rust Tracing Fields" => %{"name" => "BatchSpanProcessor.ExportError"}
      }
    }
    |> Map.merge(attrs)
    |> SentryEvent.parse()
  end
end
