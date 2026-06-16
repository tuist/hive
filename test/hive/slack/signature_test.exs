defmodule Hive.Slack.SignatureTest do
  use ExUnit.Case, async: true

  alias Hive.Slack.Signature

  @secret "shhhh"
  @body ~s({"event":"ping"})
  @now 1_700_000_000

  defp valid_signature(body, timestamp, secret) do
    base = "v0:#{timestamp}:#{body}"
    hex = :hmac |> :crypto.mac(:sha256, secret, base) |> Base.encode16(case: :lower)
    "v0=#{hex}"
  end

  test "verify/5 accepts a known good signature" do
    timestamp = Integer.to_string(@now)
    signature = valid_signature(@body, timestamp, @secret)

    assert :ok = Signature.verify(@body, signature, timestamp, @secret, @now)
  end

  test "verify/5 rejects a tampered body" do
    timestamp = Integer.to_string(@now)
    signature = valid_signature(@body, timestamp, @secret)

    assert {:error, :invalid_signature} =
             Signature.verify(@body <> "x", signature, timestamp, @secret, @now)
  end

  test "verify/5 rejects an expired timestamp" do
    expired = @now - 600
    timestamp = Integer.to_string(expired)
    signature = valid_signature(@body, timestamp, @secret)

    assert {:error, :expired_timestamp} =
             Signature.verify(@body, signature, timestamp, @secret, @now)
  end

  test "verify/5 rejects a malformed signature header" do
    timestamp = Integer.to_string(@now)

    assert {:error, :invalid_signature} =
             Signature.verify(@body, "v0=nothex", timestamp, @secret, @now)
  end

  test "verify/5 rejects a signature missing the v0 prefix" do
    timestamp = Integer.to_string(@now)
    "v0=" <> hex = valid_signature(@body, timestamp, @secret)

    assert {:error, :invalid_signature} =
             Signature.verify(@body, hex, timestamp, @secret, @now)
  end

  test "verify/5 rejects a non-numeric timestamp" do
    signature = valid_signature(@body, "0", @secret)

    assert {:error, :invalid_timestamp} =
             Signature.verify(@body, signature, "abc", @secret, @now)
  end
end
