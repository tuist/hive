defmodule HiveWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint HiveWeb.Endpoint

      use HiveWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import HiveWeb.ConnCase
    end
  end

  setup tags do
    Hive.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Persists a user for `email` and puts them in the connection's session.
  Returns `{conn, user}`.
  """
  def sign_in(conn, email) do
    {:ok, user} =
      Hive.Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    {Plug.Test.init_test_session(conn, %{user_id: user.id}), user}
  end
end
