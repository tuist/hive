defmodule Hive.Errors.Availability do
  @moduledoc """
  Single source of truth for whether error tracking is available on
  this instance. Lives in its own module so tests can stub it via
  Mimic without touching global application env.
  """

  def enabled? do
    Application.get_env(:hive, :clickhouse_enabled, false)
  end
end
