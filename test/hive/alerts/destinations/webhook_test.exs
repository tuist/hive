defmodule Hive.Alerts.Destinations.WebhookTest do
  use Hive.DataCase, async: true

  alias Hive.Alerts.Destinations.Webhook
  alias Hive.Alerts.Rule
  alias Hive.Errors.Issue

  defp rule do
    %Rule{
      id: "11111111-1111-1111-1111-111111111111",
      project_id: "22222222-2222-2222-2222-222222222222",
      name: "Grafana",
      trigger: :regression,
      tier: :incident,
      destination_type: :webhook,
      webhook_url: "https://example.com/hooks",
      webhook_signing_secret: "supersecret"
    }
  end

  defp issue do
    %Issue{
      id: "33333333-3333-3333-3333-333333333333",
      project_id: "22222222-2222-2222-2222-222222222222",
      title: "boom",
      culprit: "MyApp.blow_up/0",
      level: :error,
      status: :unresolved,
      event_count: 3,
      first_seen: ~U[2026-09-04 10:00:00.000000Z],
      last_seen: ~U[2026-09-04 10:05:00.000000Z]
    }
  end

  test "signs the JSON body with HMAC-SHA256 of the raw request body" do
    parent = self()

    request = fn url, headers, body ->
      send(parent, {:posted, url, headers, body})
      :ok
    end

    assert :ok = Webhook.deliver(rule(), issue(), :regression, request: request)

    assert_receive {:posted, "https://example.com/hooks", headers, body}

    signature_header =
      Enum.find_value(headers, fn
        {"x-hive-signature", value} -> value
        _ -> nil
      end)

    assert signature_header
    assert String.starts_with?(signature_header, "sha256=")
    expected = "sha256=" <> hmac_hex("supersecret", body)
    assert signature_header == expected

    decoded = Jason.decode!(body)
    assert decoded["event"] == "alert.fired"
    assert decoded["rule"]["name"] == "Grafana"
    assert decoded["issue"]["title"] == "boom"
    assert is_binary(decoded["delivery_id"])
  end

  test "surfaces transport errors" do
    request = fn _url, _headers, _body -> {:error, {:webhook_transport, :nxdomain}} end

    assert {:error, {:webhook_transport, :nxdomain}} =
             Webhook.deliver(rule(), issue(), :regression, request: request)
  end

  defp hmac_hex(key, body) do
    :hmac
    |> :crypto.mac(:sha256, key, body)
    |> Base.encode16(case: :lower)
  end
end
