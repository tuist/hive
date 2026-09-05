defmodule Hive.ObanConfigTest do
  use ExUnit.Case, async: true

  alias Hive.Errors.SummaryWorker
  alias Hive.Oban.Config

  test "rescues orphaned executing jobs" do
    plugins =
      :hive
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)

    assert {Oban.Plugins.Lifeline, opts} =
             Enum.find(plugins, &match?({Oban.Plugins.Lifeline, _opts}, &1))

    assert Keyword.fetch!(opts, :rescue_after) == :timer.minutes(30)
  end

  test "reconciles the weekly Drops digest daily and on boot" do
    plugins =
      :hive
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:plugins)

    assert {Oban.Plugins.Cron, opts} =
             Enum.find(plugins, &match?({Oban.Plugins.Cron, _opts}, &1))

    crontab = Keyword.fetch!(opts, :crontab)
    assert {"@reboot", Hive.Drops.WeeklyDigestWorker} in crontab
    assert {"5 18 * * *", Hive.Drops.WeeklyDigestWorker} in crontab
  end

  test "adds the configured error summary schedule only when enabled" do
    base = Application.fetch_env!(:hive, Oban)

    disabled =
      Config.build(base, %{
        enabled: false,
        schedule: "15 8 * * 1",
        slack_channel_id: "C123"
      })

    enabled =
      Config.build(base, %{
        enabled: true,
        schedule: "15 8 * * 1",
        slack_channel_id: "C123"
      })

    refute {"15 8 * * 1", SummaryWorker} in crontab(disabled)
    assert {"15 8 * * 1", SummaryWorker} in crontab(enabled)
  end

  defp crontab(config) do
    config
    |> Keyword.fetch!(:plugins)
    |> Enum.find_value(fn
      {Oban.Plugins.Cron, opts} -> Keyword.fetch!(opts, :crontab)
      _plugin -> nil
    end)
  end
end
