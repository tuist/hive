defmodule Hive.Forage.CodingRuns.SandboxProvider do
  @moduledoc """
  Optional Hive extensions for a `Condukt.Sandbox` implementation.

  A custom coding-run provider implements `Condukt.Sandbox` and starts an
  isolated environment from `init/1`. Hive passes the selected runner name,
  image, processor, memory, disk, timeout, run identifier, and the map from
  `HIVE_CODING_SANDBOX_OPTIONS`. After initialization, Hive installs the
  configured tools, uploads the repository snapshot, and creates the Git
  baseline used to collect changes.

  The sandbox needs a Unix-compatible shell and must return `/workspace` from
  `Condukt.Sandbox.cwd/1`. The callbacks below are optional. They let Hive
  verify provider-specific configuration before accepting a run and persist
  the provider's external run identifier when one exists.
  """

  @callback configured?(provider_options :: map()) :: boolean()
  @callback runner_id(sandbox :: struct()) :: String.t() | nil

  @optional_callbacks configured?: 1, runner_id: 1
end
