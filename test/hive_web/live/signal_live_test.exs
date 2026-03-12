defmodule HiveWeb.SignalLiveTest do
  use HiveWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Hive.Accounts.User
  alias Hive.Repo
  alias Hive.Signals

  setup do
    original_public = Application.get_env(:hive, :public)
    Application.put_env(:hive, :public, true)
    on_exit(fn -> Application.put_env(:hive, :public, original_public) end)

    {:ok, signal} =
      Signals.create_signal(%{
        title: "Markdown signal",
        body: """
        ## Repro

        Please check the **failing build** and visit [the issue](https://example.com/issues/1).
        """,
        source: "github",
        status: :needs_review,
        source_author: "alice",
        source_channel: "tuist/hive",
        source_url: "https://github.com/tuist/hive/issues/1",
        source_timestamp: ~U[2026-03-12 10:00:00Z]
      })

    {:ok, message} =
      Signals.add_signal_message(signal, %{
        author: "bob",
        body: "I hit the _same failure_ on CI.",
        source_url: "https://github.com/tuist/hive/issues/1#issuecomment-1",
        source_timestamp: ~U[2026-03-12 10:30:00Z]
      })

    %{signal: signal, message: message}
  end

  test "renders markdown and source links for the signal conversation", %{
    conn: conn,
    signal: signal,
    message: message
  } do
    {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

    assert has_element?(view, "#signal")
    assert has_element?(view, "#signal-source-link[href='#{signal.source_url}']")
    assert has_element?(view, "#signal [data-part='meta']", "Needs Review")
    assert has_element?(view, "#signal [data-part='body'] strong", "failing build")
    assert has_element?(view, "#signal [data-part='body'] a[href='https://example.com/issues/1']")
    assert has_element?(view, "#message-#{message.id} [data-part='message-author']", "bob")
    assert has_element?(view, "#message-source-link-#{message.id}[href='#{message.source_url}']")
    assert has_element?(view, "#message-#{message.id} [data-part='body'] em", "same failure")
    refute has_element?(view, "#signal-status-select")
  end

  test "authenticated users can update the signal status", %{conn: conn, signal: signal} do
    {:ok, user} =
      %User{}
      |> User.changeset(%{email: "alice@example.com", name: "Alice"})
      |> Repo.insert()

    conn = init_test_session(conn, %{"user_id" => user.id})

    {:ok, view, _html} = live(conn, ~p"/signals/#{signal.id}")

    assert has_element?(view, "#signal-status-select")

    render_hook(view, "select_status", %{"value" => ["resolved"]})

    assert has_element?(view, "#signal [data-part='meta']", "Resolved")
    assert Signals.get_signal(signal.id).status == :resolved
  end
end
