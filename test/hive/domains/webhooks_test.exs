defmodule Hive.Domains.WebhooksTest do
  use Hive.DataCase, async: true

  alias Hive.Domains
  alias Hive.Domains.Webhook
  alias Hive.Domains.Webhooks

  setup do
    {:ok, domain} = Domains.create_domain(%{name: "Hive"})
    {:ok, domain: domain}
  end

  test "create/2 returns the plaintext token once and persists only the hash", %{domain: domain} do
    {:ok, {webhook, token}} =
      Webhooks.create(domain, %{"name" => "Grafana prod", "source" => "grafana"})

    assert %Webhook{name: "Grafana prod", source: :grafana} = webhook
    assert String.starts_with?(token, "hwh_")
    refute webhook.token_hash == token
    assert webhook.token_hash == :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  test "create/2 ignores unknown string keys without converting them to atoms", %{domain: domain} do
    assert {:ok, {webhook, _token}} =
             Webhooks.create(domain, %{
               "name" => "Grafana prod",
               "source" => "grafana",
               "unexpected_attribute" => "ignored"
             })

    assert %Webhook{name: "Grafana prod", source: :grafana} = webhook
  end

  test "find_by_token/3 returns the webhook for the right domain+source+token", %{
    domain: domain
  } do
    {:ok, {webhook, token}} =
      Webhooks.create(domain, %{"name" => "Grafana", "source" => "grafana"})

    assert %Webhook{id: id} = Webhooks.find_by_token(domain.id, :grafana, token)
    assert id == webhook.id
  end

  test "find_by_token/3 rejects a wrong token", %{domain: domain} do
    {:ok, _} = Webhooks.create(domain, %{"name" => "Grafana", "source" => "grafana"})

    assert Webhooks.find_by_token(domain.id, :grafana, "hwh_wrong") == nil
  end

  test "find_by_token/3 rejects a token from a different domain", %{domain: domain} do
    {:ok, other} = Domains.create_domain(%{name: "Atlas"})
    {:ok, {_webhook, token}} = Webhooks.create(other, %{"name" => "G", "source" => "grafana"})

    assert Webhooks.find_by_token(domain.id, :grafana, token) == nil
  end

  test "list_for_domain/1 lists all webhooks for the domain", %{domain: domain} do
    {:ok, {first, _}} = Webhooks.create(domain, %{"name" => "A", "source" => "grafana"})
    {:ok, {second, _}} = Webhooks.create(domain, %{"name" => "B", "source" => "grafana"})

    ids = Webhooks.list_for_domain(domain) |> Enum.map(& &1.id) |> Enum.sort()
    assert ids == Enum.sort([first.id, second.id])
  end

  test "list_for_domain/1 scopes to the given domain", %{domain: domain} do
    {:ok, {mine, _}} = Webhooks.create(domain, %{"name" => "A", "source" => "grafana"})
    {:ok, other} = Domains.create_domain(%{name: "Atlas"})
    {:ok, _} = Webhooks.create(other, %{"name" => "B", "source" => "grafana"})

    assert [%{id: id}] = Webhooks.list_for_domain(domain)
    assert id == mine.id
  end

  test "delete/1 removes the webhook", %{domain: domain} do
    {:ok, {webhook, _}} = Webhooks.create(domain, %{"name" => "A", "source" => "grafana"})
    {:ok, _} = Webhooks.delete(webhook)

    assert Webhooks.list_for_domain(domain) == []
  end

  test "ingest_webhook/4 upserts a Grafana delivery for the domain", %{domain: domain} do
    {:ok, {webhook, _token}} = Webhooks.create(domain, %{"name" => "G", "source" => "grafana"})

    assert {:ok, [alert]} =
             Domains.ingest_webhook(:grafana, domain, webhook, %{
               "alerts" => [
                 %{
                   "status" => "firing",
                   "fingerprint" => "fp-1",
                   "labels" => %{"alertname" => "HighLatency"}
                 }
               ]
             })

    assert alert.domain_id == domain.id
    assert alert.webhook_id == webhook.id
    assert alert.title == "HighLatency"
  end
end
