defmodule Hive.Slack.InteractionsTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Audit.Activity
  alias Hive.Forage.FeatureRequest
  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Slack.Interactions

  defp installation! do
    suffix = System.unique_integer([:positive])

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{suffix}",
        team_name: "Workspace #{suffix}",
        bot_token: "xoxb-#{suffix}",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    installation
  end

  defp capture_payload(opts) do
    %{
      "type" => "message_action",
      "callback_id" => Keyword.get(opts, :callback_id, "capture_feature_request"),
      "team" => %{"id" => Keyword.get(opts, :team_id, "T1")},
      "user" => %{"id" => "U-invoker"},
      "message" => %{
        "text" => Keyword.get(opts, :text, "We should ship dark mode soon."),
        "permalink" => "https://slack.example/archives/C/p1"
      },
      "response_url" => Keyword.get(opts, :response_url, "https://hooks.slack/respond")
    }
  end

  test "capture_feature_request creates a feature request when the Slack user maps to a Hive user" do
    installation = installation!()

    {:ok, _user} =
      Accounts.upsert_from_auth(%{
        email: "alice@example.com",
        provider: "test",
        provider_uid: "alice"
      })

    stub(API, :get_user, fn ^installation, "U-invoker" ->
      {:ok, %{"ok" => true, "user" => %{"profile" => %{"email" => "alice@example.com"}}}}
    end)

    stub(API, :post_response, fn _url, body ->
      assert body["response_type"] == "ephemeral"
      assert body["text"] =~ "forage item"
      :ok
    end)

    assert :ok = Interactions.handle(capture_payload([]), installation)

    assert [%FeatureRequest{title: title, description: description}] = Repo.all(FeatureRequest)
    assert String.starts_with?(title, "We should ship dark mode soon")
    assert description =~ "dark mode"

    assert %Activity{interface: "webhook"} =
             Repo.get_by!(Activity, action: "slack.forage_item.captured")

    assert %Activity{interface: "webhook"} =
             Repo.get_by!(Activity, action: "forage.intake.created")
  end

  test "capture_feature_request returns an ephemeral error when the Slack user has no Hive match" do
    installation = installation!()

    stub(API, :get_user, fn ^installation, "U-invoker" ->
      {:ok, %{"ok" => true, "user" => %{"profile" => %{"email" => "nobody@example.com"}}}}
    end)

    stub(API, :post_response, fn _url, body ->
      assert body["text"] =~ "couldn't match"
      :ok
    end)

    assert :ok = Interactions.handle(capture_payload([]), installation)
    assert Repo.all(FeatureRequest) == []
  end

  test "capture_forage_item callback creates a forage item" do
    installation = installation!()

    {:ok, _user} =
      Accounts.upsert_from_auth(%{
        email: "forage-callback@example.com",
        provider: "test",
        provider_uid: "forage-callback"
      })

    stub(API, :get_user, fn ^installation, "U-invoker" ->
      {:ok,
       %{
         "ok" => true,
         "user" => %{"profile" => %{"email" => "forage-callback@example.com"}}
       }}
    end)

    stub(API, :post_response, fn _url, _body -> :ok end)

    assert :ok =
             Interactions.handle(
               capture_payload(callback_id: "capture_forage_item"),
               installation
             )

    assert [%FeatureRequest{title: title}] = Repo.all(FeatureRequest)
    assert String.starts_with?(title, "We should ship dark mode soon")
  end

  test "unknown callback_ids are no-ops" do
    installation = installation!()
    reject(&API.get_user/2)

    payload = %{
      "type" => "message_action",
      "callback_id" => "something_else",
      "team" => %{"id" => "T1"},
      "user" => %{"id" => "U-1"},
      "message" => %{"text" => "x"}
    }

    assert :ok = Interactions.handle(payload, installation)
  end

  test "block_actions returns :ok without dispatching" do
    installation = installation!()
    reject(&API.get_user/2)

    assert :ok = Interactions.handle(%{"type" => "block_actions"}, installation)
  end
end
