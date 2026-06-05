defmodule Hive.GitHub.WebhooksTest do
  use ExUnit.Case, async: true

  alias Hive.GitHub.Webhooks

  @secret "webhook-secret"
  @body ~s({"action":"ping"})

  test "verifies a matching SHA-256 webhook signature" do
    assert Webhooks.verify_signature(@body, signature(@body, @secret), @secret) == :ok
  end

  test "rejects a signature generated with another secret" do
    assert Webhooks.verify_signature(@body, signature(@body, "other-secret"), @secret) ==
             {:error, :invalid_signature}
  end

  test "rejects a missing signature" do
    assert Webhooks.verify_signature(@body, nil, @secret) == {:error, :missing_signature}
  end

  defp signature(body, secret) do
    digest =
      :hmac
      |> :crypto.mac(:sha256, secret, body)
      |> Base.encode16(case: :lower)

    "sha256=#{digest}"
  end
end
