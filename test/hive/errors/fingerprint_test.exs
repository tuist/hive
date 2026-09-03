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
    end

    test "returns a 64-character lowercase hex digest" do
      digest = Fingerprint.compute(SentryEvent.parse(%{}))
      assert String.length(digest) == 64
      assert digest == String.downcase(digest)
      assert digest =~ ~r/^[0-9a-f]+$/
    end
  end
end
