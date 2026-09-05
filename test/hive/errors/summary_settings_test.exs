defmodule Hive.Errors.SummarySettingsTest do
  use Hive.DataCase, async: true

  alias Hive.Errors.Summaries
  alias Hive.Errors.SummarySettings

  test "creates runtime settings from the launch-time defaults" do
    assert %SummarySettings{
             id: "default",
             enabled: false,
             schedule: "0 9 * * *",
             slack_channel_id: nil
           } = Summaries.settings()
  end

  test "updates and reloads runtime settings" do
    settings = Summaries.settings()

    assert {:ok, %SummarySettings{} = updated} =
             Summaries.update_settings(settings, %{
               "enabled" => "true",
               "schedule" => "15 8 * * 1",
               "slack_channel_id" => " C123 "
             })

    assert updated.enabled
    assert updated.schedule == "15 8 * * 1"
    assert updated.slack_channel_id == "C123"

    assert Summaries.config() == %{
             enabled: true,
             schedule: "15 8 * * 1",
             slack_channel_id: "C123"
           }
  end

  test "requires a valid schedule and a channel when enabled" do
    changeset =
      Summaries.change_settings(Summaries.settings(), %{
        "enabled" => "true",
        "schedule" => "whenever",
        "slack_channel_id" => ""
      })

    assert {"must be a valid five-field Cron schedule", []} = changeset.errors[:schedule]
    assert {"can't be blank", [validation: :required]} = changeset.errors[:slack_channel_id]
  end

  test "matches enabled schedules at runtime" do
    config = %{enabled: true, schedule: "15 8 * * 1", slack_channel_id: "C123"}

    assert Summaries.due?(~U[2026-09-07 08:15:00Z], config)
    refute Summaries.due?(~U[2026-09-07 08:16:00Z], config)
    refute Summaries.due?(~U[2026-09-07 08:15:00Z], %{config | enabled: false})
  end

  test "does not create a reporting period between scheduled times" do
    assert {:ok, nil, :not_due} =
             Summaries.reconcile(
               config: %{enabled: true, schedule: "15 8 * * 1", slack_channel_id: "C123"},
               scheduled_for: ~U[2026-09-07 08:16:00Z]
             )
  end
end
