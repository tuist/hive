defmodule Hive.AlertsTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Alerts
  alias Hive.Alerts.Notification
  alias Hive.Alerts.Rule
  alias Hive.Alerts.Workers.DeliverRule
  alias Hive.Errors
  alias Hive.Errors.SentryEvent
  alias Hive.Projects
  alias Hive.Repo
  alias Hive.Slack.Installation

  setup :verify_on_exit!

  setup do
    stub(Hive.Errors.Availability, :enabled?, fn -> true end)
    stub(Hive.Errors.Event.Buffer, :insert, fn row -> {:ok, row} end)

    {:ok, project} = Projects.create_project(%{"name" => "Widgets"})

    installation =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{System.unique_integer([:positive])}",
        team_name: "Test workspace",
        bot_user_id: "U0",
        bot_token: "xoxb-test",
        scope: "chat:write",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert!()

    {:ok, project: project, installation: installation}
  end

  defp rule_attrs(installation, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Fresh crashes",
        "trigger" => "new_issue_threshold",
        "threshold_event_count" => 3,
        "threshold_window_minutes" => 60,
        "tier" => "attention",
        "cooldown_minutes" => 30,
        "destination_type" => "slack",
        "slack_installation_id" => installation.id,
        "slack_channel_id" => "C123",
        "slack_mention" => "none"
      },
      overrides
    )
  end

  describe "create_rule/2" do
    test "creates a valid rule", %{project: project, installation: installation} do
      assert {:ok, %Rule{name: "Fresh crashes", tier: :attention}} =
               Alerts.create_rule(project, rule_attrs(installation))
    end

    test "requires a Slack workspace + channel when destination is slack", %{project: project} do
      attrs = %{
        "name" => "No destination",
        "trigger" => "regression",
        "tier" => "attention",
        "destination_type" => "slack"
      }

      assert {:error, changeset} = Alerts.create_rule(project, attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :slack_installation_id)
    end

    test "creates a webhook rule and mints a signing secret", %{project: project} do
      attrs = %{
        "name" => "Grafana",
        "trigger" => "regression",
        "tier" => "incident",
        "destination_type" => "webhook",
        "webhook_url" => "https://example.com/hooks/hive"
      }

      assert {:ok, rule} = Alerts.create_rule(project, attrs)
      assert rule.destination_type == :webhook
      assert rule.webhook_url == "https://example.com/hooks/hive"
      assert is_binary(rule.webhook_signing_secret)
      assert String.length(rule.webhook_signing_secret) == 64
    end

    test "rejects a webhook rule with a bad URL", %{project: project} do
      attrs = %{
        "name" => "Bad URL",
        "trigger" => "regression",
        "tier" => "attention",
        "destination_type" => "webhook",
        "webhook_url" => "not-a-url"
      }

      assert {:error, changeset} = Alerts.create_rule(project, attrs)
      assert Keyword.has_key?(changeset.errors, :webhook_url)
    end

    test "clears threshold fields for triggers that don't need them", %{
      project: project,
      installation: installation
    } do
      {:ok, rule} =
        Alerts.create_rule(project, rule_attrs(installation, %{"trigger" => "regression"}))

      assert rule.threshold_event_count == nil
      assert rule.threshold_window_minutes == nil
    end
  end

  describe "matching_rules_for_issue/3 with new_issue_threshold" do
    test "does not fire before threshold is reached", %{
      project: project,
      installation: installation
    } do
      {:ok, _rule} =
        Alerts.create_rule(project, rule_attrs(installation, %{"threshold_event_count" => 5}))

      {:ok, issue} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "boom"}))

      before = %{issue | event_count: 0}
      assert Alerts.matching_rules_for_issue(issue, before, %{environment: nil}) == []
    end

    test "fires once the issue crosses the threshold within the window", %{
      project: project,
      installation: installation
    } do
      {:ok, %Rule{id: rule_id}} =
        Alerts.create_rule(project, rule_attrs(installation, %{"threshold_event_count" => 2}))

      {:ok, issue} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "sideways"}))

      # Simulate the coalescer having bumped the counter to 2.
      {:ok, issue} = Repo.update(Ecto.Changeset.change(issue, event_count: 2))

      before = %{issue | event_count: 1}
      matches = Alerts.matching_rules_for_issue(issue, before, %{environment: nil})

      assert [{%Rule{id: ^rule_id}, :new_issue_threshold}] = matches
    end
  end

  describe "matching_rules_for_issue/3 with regression" do
    test "fires only on resolved -> unresolved", %{
      project: project,
      installation: installation
    } do
      {:ok, %Rule{id: rule_id}} =
        Alerts.create_rule(project, rule_attrs(installation, %{"trigger" => "regression"}))

      {:ok, issue} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "reopens"}))

      {:ok, resolved} = Errors.update_issue_status(issue, :resolved)
      {:ok, reopened} = Errors.update_issue_status(resolved, :unresolved)

      before = %{reopened | status: resolved.status}

      matches = Alerts.matching_rules_for_issue(reopened, before, %{environment: nil})
      assert [{%Rule{id: ^rule_id}, :regression}] = matches
    end

    test "does not fire on a plain repeat", %{project: project, installation: installation} do
      {:ok, _rule} =
        Alerts.create_rule(project, rule_attrs(installation, %{"trigger" => "regression"}))

      {:ok, issue} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "again"}))

      before = %{issue | event_count: 0}

      assert Alerts.matching_rules_for_issue(issue, before, %{environment: nil}) == []
    end
  end

  describe "in_cooldown?/2" do
    test "true within window, false after", %{project: project, installation: installation} do
      {:ok, rule} = Alerts.create_rule(project, rule_attrs(installation))

      {:ok, issue} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "z"}))

      {:ok, _notification} =
        Alerts.record_notification(%{
          rule_id: rule.id,
          subject_type: "error_issue",
          subject_id: issue.id,
          status: "sent",
          fired_at: DateTime.utc_now()
        })

      assert Alerts.in_cooldown?(rule, issue.id)

      # Backdate the fired_at row past the window.
      Repo.update_all(Notification,
        set: [fired_at: DateTime.add(DateTime.utc_now(), -60 * 60, :second)]
      )

      refute Alerts.in_cooldown?(rule, issue.id)
    end
  end

  describe "evaluate_error_issue/3 integration" do
    # `Hive.Errors.record_event/2` casts through the IssueCoalescer so
    # the alerts pipeline fires from the coalescer's flush, not from
    # the request path. The coalescer is exercised end-to-end in
    # `Hive.Errors.IssueCoalescerTest`; here we assert the wiring:
    # `evaluate_error_issue/3` enqueues a `DeliverRule` job when a
    # rule matches, and does not otherwise.
    test "enqueues a delivery job for a matching rule", %{
      project: project,
      installation: installation
    } do
      {:ok, %Rule{id: rule_id}} =
        Alerts.create_rule(
          project,
          rule_attrs(installation, %{"threshold_event_count" => 1})
        )

      {:ok, issue} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "hi"}))

      Alerts.evaluate_error_issue(issue, %{status: :unresolved, resolved_at: nil}, %{
        environment: nil
      })

      assert_enqueued(
        worker: DeliverRule,
        args: %{"rule_id" => rule_id, "reason" => "new_issue_threshold"}
      )
    end

    test "does not enqueue when no rule matches", %{project: project} do
      {:ok, issue} =
        Hive.ErrorsHelpers.seed_issue(project, SentryEvent.parse(%{"message" => "silent"}))

      Alerts.evaluate_error_issue(issue, %{status: :unresolved, resolved_at: nil}, %{
        environment: nil
      })

      refute_enqueued(worker: DeliverRule)
    end
  end
end
