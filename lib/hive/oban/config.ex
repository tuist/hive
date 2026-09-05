defmodule Hive.Oban.Config do
  @moduledoc false

  alias Hive.Errors.Summaries
  alias Hive.Errors.SummaryWorker

  def build(oban_config, error_summary_config \\ Summaries.config()) do
    if error_summary_config.enabled do
      Keyword.update!(oban_config, :plugins, fn plugins ->
        Enum.map(plugins, &add_error_summary_schedule(&1, error_summary_config.schedule))
      end)
    else
      oban_config
    end
  end

  defp add_error_summary_schedule({Oban.Plugins.Cron, opts}, schedule) do
    {Oban.Plugins.Cron, Keyword.update!(opts, :crontab, &(&1 ++ [{schedule, SummaryWorker}]))}
  end

  defp add_error_summary_schedule(plugin, _schedule), do: plugin
end
