defmodule Hive.Projects.WebhooksTest do
  use Hive.DataCase, async: true

  alias Hive.Projects
  alias Hive.Projects.Webhook
  alias Hive.Projects.Webhooks

  setup do
    project = create_project!()
    {:ok, project: project}
  end

  test "create/2 returns the plaintext token once and persists only the hash", %{project: project} do
    {:ok, {webhook, token}} =
      Webhooks.create(project, %{"name" => "Grafana prod", "source" => "grafana"})

    assert %Webhook{name: "Grafana prod", source: :grafana} = webhook
    assert String.starts_with?(token, "hwh_")
    refute webhook.token_hash == token
    assert webhook.token_hash == :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  test "create/2 ignores unknown string keys without converting them to atoms", %{
    project: project
  } do
    assert {:ok, {webhook, _token}} =
             Webhooks.create(project, %{
               "name" => "Grafana prod",
               "source" => "grafana",
               "unexpected_attribute" => "ignored"
             })

    assert %Webhook{name: "Grafana prod", source: :grafana} = webhook
  end

  test "find_by_token/3 returns the webhook for the right project+source+token", %{
    project: project
  } do
    {:ok, {webhook, token}} =
      Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    assert %Webhook{id: id} = Webhooks.find_by_token(project.id, :grafana, token)
    assert id == webhook.id
  end

  test "find_by_token/3 rejects a wrong token", %{project: project} do
    {:ok, _} = Webhooks.create(project, %{"name" => "Grafana", "source" => "grafana"})

    assert Webhooks.find_by_token(project.id, :grafana, "hwh_wrong") == nil
  end

  test "find_by_token/3 rejects a token from a different project", %{project: project} do
    other = create_project!()
    {:ok, {_webhook, token}} = Webhooks.create(other, %{"name" => "G", "source" => "grafana"})

    assert Webhooks.find_by_token(project.id, :grafana, token) == nil
  end

  test "list_for_project/1 lists all webhooks for the project", %{project: project} do
    {:ok, {first, _}} = Webhooks.create(project, %{"name" => "A", "source" => "grafana"})
    {:ok, {second, _}} = Webhooks.create(project, %{"name" => "B", "source" => "grafana"})

    ids = Webhooks.list_for_project(project) |> Enum.map(& &1.id) |> Enum.sort()
    assert ids == Enum.sort([first.id, second.id])
  end

  test "list_for_project/1 scopes to the given project", %{project: project} do
    {:ok, {mine, _}} = Webhooks.create(project, %{"name" => "A", "source" => "grafana"})
    {:ok, _} = Webhooks.create(create_project!(), %{"name" => "B", "source" => "grafana"})

    assert [%{id: id}] = Webhooks.list_for_project(project)
    assert id == mine.id
  end

  test "delete/1 removes the webhook", %{project: project} do
    {:ok, {webhook, _}} = Webhooks.create(project, %{"name" => "A", "source" => "grafana"})
    {:ok, _} = Webhooks.delete(webhook)

    assert Webhooks.list_for_project(project) == []
  end

  test "ingest_webhook/4 upserts a Grafana delivery for the project", %{project: project} do
    {:ok, {webhook, _token}} = Webhooks.create(project, %{"name" => "G", "source" => "grafana"})

    assert {:ok, [alert]} =
             Projects.ingest_webhook(:grafana, project, webhook, %{
               "alerts" => [
                 %{
                   "status" => "firing",
                   "fingerprint" => "fp-1",
                   "labels" => %{"alertname" => "HighLatency"}
                 }
               ]
             })

    assert alert.project_id == project.id
    assert alert.domain_id == nil
    assert alert.webhook_id == webhook.id
    assert alert.title == "HighLatency"
  end

  defp create_project! do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    project
  end
end
