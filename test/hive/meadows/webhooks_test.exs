defmodule Hive.Meadows.WebhooksTest do
  use Hive.DataCase, async: true

  alias Hive.Meadows
  alias Hive.Meadows.Webhook
  alias Hive.Meadows.Webhooks

  setup do
    {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})
    {:ok, meadow: meadow}
  end

  test "create/2 returns the plaintext token once and persists only the hash", %{meadow: meadow} do
    {:ok, {webhook, token}} =
      Webhooks.create(meadow, %{"name" => "Grafana prod", "source" => "grafana"})

    assert %Webhook{name: "Grafana prod", source: :grafana} = webhook
    assert String.starts_with?(token, "hwh_")
    refute webhook.token_hash == token
    assert webhook.token_hash == :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  test "find_by_token/3 returns the webhook for the right meadow+source+token", %{
    meadow: meadow
  } do
    {:ok, {webhook, token}} =
      Webhooks.create(meadow, %{"name" => "Grafana", "source" => "grafana"})

    assert %Webhook{id: id} = Webhooks.find_by_token(meadow.id, :grafana, token)
    assert id == webhook.id
  end

  test "find_by_token/3 rejects a wrong token", %{meadow: meadow} do
    {:ok, _} = Webhooks.create(meadow, %{"name" => "Grafana", "source" => "grafana"})

    assert Webhooks.find_by_token(meadow.id, :grafana, "hwh_wrong") == nil
  end

  test "find_by_token/3 rejects a token from a different meadow", %{meadow: meadow} do
    {:ok, other} = Meadows.create_meadow(%{name: "Atlas"})
    {:ok, {_webhook, token}} = Webhooks.create(other, %{"name" => "G", "source" => "grafana"})

    assert Webhooks.find_by_token(meadow.id, :grafana, token) == nil
  end

  test "list_for_meadow/1 lists all webhooks for the meadow", %{meadow: meadow} do
    {:ok, {first, _}} = Webhooks.create(meadow, %{"name" => "A", "source" => "grafana"})
    {:ok, {second, _}} = Webhooks.create(meadow, %{"name" => "B", "source" => "grafana"})

    ids = Webhooks.list_for_meadow(meadow) |> Enum.map(& &1.id) |> Enum.sort()
    assert ids == Enum.sort([first.id, second.id])
  end

  test "list_for_meadow/1 scopes to the given meadow", %{meadow: meadow} do
    {:ok, {mine, _}} = Webhooks.create(meadow, %{"name" => "A", "source" => "grafana"})
    {:ok, other} = Meadows.create_meadow(%{name: "Atlas"})
    {:ok, _} = Webhooks.create(other, %{"name" => "B", "source" => "grafana"})

    assert [%{id: id}] = Webhooks.list_for_meadow(meadow)
    assert id == mine.id
  end

  test "delete/1 removes the webhook", %{meadow: meadow} do
    {:ok, {webhook, _}} = Webhooks.create(meadow, %{"name" => "A", "source" => "grafana"})
    {:ok, _} = Webhooks.delete(webhook)

    assert Webhooks.list_for_meadow(meadow) == []
  end

  test "ingest_webhook/4 upserts a Grafana delivery for the meadow", %{meadow: meadow} do
    {:ok, {webhook, _token}} = Webhooks.create(meadow, %{"name" => "G", "source" => "grafana"})

    assert {:ok, [alert]} =
             Meadows.ingest_webhook(:grafana, meadow, webhook, %{
               "alerts" => [
                 %{
                   "status" => "firing",
                   "fingerprint" => "fp-1",
                   "labels" => %{"alertname" => "HighLatency"}
                 }
               ]
             })

    assert alert.meadow_id == meadow.id
    assert alert.webhook_id == webhook.id
    assert alert.title == "HighLatency"
  end
end
