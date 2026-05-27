defmodule HiveWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint HiveWeb.Endpoint

      use HiveWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import HiveWeb.ConnCase
    end
  end

  setup tags do
    Hive.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
