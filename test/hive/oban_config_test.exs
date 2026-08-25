defmodule Hive.ObanConfigTest do
  use ExUnit.Case, async: true

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
end
