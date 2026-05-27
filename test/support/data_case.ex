defmodule Hive.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Hive.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Hive.DataCase
    end
  end

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Hive.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
