defmodule Hive.Products.WebhooksTest do
  use Hive.DataCase, async: true

  alias Hive.Products
  alias Hive.Products.Webhook
  alias Hive.Products.Webhooks

  setup do
    {:ok, product} = Products.create_product(%{name: "Hive"})
    {:ok, product: product}
  end

  test "create/2 returns the plaintext token once and persists only the hash", %{product: product} do
    {:ok, {webhook, token}} =
      Webhooks.create(product, %{"name" => "Grafana prod", "source" => "grafana"})

    assert %Webhook{name: "Grafana prod", source: :grafana} = webhook
    assert String.starts_with?(token, "hwh_")
    refute webhook.token_hash == token
    assert webhook.token_hash == :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  test "find_by_token/3 returns the webhook for the right product+source+token", %{
    product: product
  } do
    {:ok, {webhook, token}} =
      Webhooks.create(product, %{"name" => "Grafana", "source" => "grafana"})

    assert %Webhook{id: id} = Webhooks.find_by_token(product.id, :grafana, token)
    assert id == webhook.id
  end

  test "find_by_token/3 rejects a wrong token", %{product: product} do
    {:ok, _} = Webhooks.create(product, %{"name" => "Grafana", "source" => "grafana"})

    assert Webhooks.find_by_token(product.id, :grafana, "hwh_wrong") == nil
  end

  test "find_by_token/3 rejects a token from a different product", %{product: product} do
    {:ok, other} = Products.create_product(%{name: "Atlas"})
    {:ok, {_webhook, token}} = Webhooks.create(other, %{"name" => "G", "source" => "grafana"})

    assert Webhooks.find_by_token(product.id, :grafana, token) == nil
  end

  test "list_for_product/1 lists all webhooks for the product", %{product: product} do
    {:ok, {first, _}} = Webhooks.create(product, %{"name" => "A", "source" => "grafana"})
    {:ok, {second, _}} = Webhooks.create(product, %{"name" => "B", "source" => "grafana"})

    ids = Webhooks.list_for_product(product) |> Enum.map(& &1.id) |> Enum.sort()
    assert ids == Enum.sort([first.id, second.id])
  end

  test "list_for_product/1 scopes to the given product", %{product: product} do
    {:ok, {mine, _}} = Webhooks.create(product, %{"name" => "A", "source" => "grafana"})
    {:ok, other} = Products.create_product(%{name: "Atlas"})
    {:ok, _} = Webhooks.create(other, %{"name" => "B", "source" => "grafana"})

    assert [%{id: id}] = Webhooks.list_for_product(product)
    assert id == mine.id
  end

  test "delete/1 removes the webhook", %{product: product} do
    {:ok, {webhook, _}} = Webhooks.create(product, %{"name" => "A", "source" => "grafana"})
    {:ok, _} = Webhooks.delete(webhook)

    assert Webhooks.list_for_product(product) == []
  end
end
