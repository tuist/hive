defmodule HiveWeb.SignalsLiveTest do
  use HiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hive.Signals

  setup do
    original_public = Application.get_env(:hive, :public)
    Application.put_env(:hive, :public, true)
    on_exit(fn -> Application.put_env(:hive, :public, original_public) end)

    {:ok, signal} =
      Signals.create_signal(%{
        title: "Signals row navigation",
        source: "github",
        source_author: "alice",
        source_channel: "tuist/hive"
      })

    %{signal: signal}
  end

  test "renders row-level navigation for each signal", %{conn: conn, signal: signal} do
    {:ok, view, _html} = live(conn, ~p"/signals")

    assert has_element?(view, ~s(tr[id="#{signal.id}"][phx-click]))
  end
end
