defmodule Hive.Alerts.Workers.DeliverRuleTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Alerts
  alias Hive.Alerts.Notification
  alias Hive.Alerts.Workers.DeliverRule
  alias Hive.Errors.SentryEvent
  alias Hive.Projects
  alias Hive.Slack.Installation

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)

    {:ok, project} = Projects.create_project(%{"name" => "Widgets"})

    installation =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{System.unique_integer([:positive])}",
        team_name: "Test",
        bot_user_id: "U0",
        bot_token: "xoxb-test",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

    {:ok, rule} =
      Alerts.create_rule(project, %{
        "name" => "Regressions",
        "trigger" => "regression",
        "tier" => "incident",
        "destination_type" => "slack",
        "slack_installation_id" => installation.id,
        "slack_channel_id" => "C42",
        "slack_mention" => "here",
        "cooldown_minutes" => 5
      })

    {:ok, issue} =
      Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "boom"}))

    {:ok, rule: rule, issue: issue}
  end

  defp job(rule, issue, reason \\ "regression") do
    %Oban.Job{
      args: %{
        "rule_id" => rule.id,
        "subject_type" => "error_issue",
        "subject_id" => issue.id,
        "reason" => reason
      }
    }
  end

  test "posts a Slack message and records a sent notification", %{rule: rule, issue: issue} do
    expect(Hive.Slack.API, :post_message, fn _installation, params ->
      assert params["channel"] == "C42"
      assert params["text"] =~ "Incident"
      # Mention prefix lives in a real `section` block since Slack's
      # `header` block strips mention syntax.
      mention_block =
        Enum.find(params["blocks"], fn
          %{"type" => "section", "text" => %{"text" => text}} -> text =~ "<!here>"
          _ -> false
        end)

      assert mention_block, "expected a section block carrying <!here>"
      {:ok, %{"ok" => true, "ts" => "1.0"}}
    end)

    assert :ok = DeliverRule.perform(job(rule, issue))

    assert [%Notification{status: :sent, subject_id: subject_id}] = Repo.all(Notification)
    assert subject_id == issue.id
  end

  test "skips when in cooldown and does not call Slack", %{rule: rule, issue: issue} do
    reject(&Hive.Slack.API.post_message/2)

    {:ok, _} =
      Alerts.record_notification(%{
        rule_id: rule.id,
        subject_type: "error_issue",
        subject_id: issue.id,
        status: "sent",
        fired_at: DateTime.utc_now()
      })

    assert :ok = DeliverRule.perform(job(rule, issue))

    statuses = Notification |> Repo.all() |> Enum.map(& &1.status) |> Enum.sort()
    assert :sent in statuses
    assert :skipped in statuses
  end

  test "records a failed notification when Slack rejects", %{rule: rule, issue: issue} do
    expect(Hive.Slack.API, :post_message, fn _installation, _params ->
      {:error, {:slack_api_error, "channel_not_found"}}
    end)

    assert {:error, _} = DeliverRule.perform(job(rule, issue))

    assert [%Notification{status: :failed}] = Repo.all(Notification)
  end
end
