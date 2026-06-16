defmodule Hive.Slack.APITest do
  use ExUnit.Case, async: true
  use Mimic

  alias Hive.Slack.API
  alias Hive.Slack.Installation

  defp connected_installation do
    %Installation{id: "i-1", team_id: "T1", bot_token: "xoxb-test"}
  end

  defp disconnected_installation do
    %Installation{
      id: "i-2",
      team_id: "T2",
      bot_token: nil,
      disconnected_at: DateTime.utc_now()
    }
  end

  test "post_message/2 sends the bot token as a Bearer header and JSON body" do
    stub(Req, :post, fn url, opts ->
      assert url == "https://slack.com/api/chat.postMessage"
      headers = Keyword.fetch!(opts, :headers)
      assert {"authorization", "Bearer xoxb-test"} in headers
      assert Keyword.fetch!(opts, :json) == %{"channel" => "C1", "text" => "hi"}

      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "ts" => "1.0"}}}
    end)

    assert {:ok, %{"ok" => true, "ts" => "1.0"}} =
             API.post_message(connected_installation(), %{"channel" => "C1", "text" => "hi"})
  end

  test "get_user/2 issues a GET with the user param" do
    stub(Req, :get, fn url, opts ->
      assert url == "https://slack.com/api/users.info"
      assert Keyword.fetch!(opts, :params) == %{"user" => "U1"}
      assert {"authorization", "Bearer xoxb-test"} in Keyword.fetch!(opts, :headers)

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"ok" => true, "user" => %{"profile" => %{"email" => "alice@example.com"}}}
       }}
    end)

    assert {:ok, %{"ok" => true}} = API.get_user(connected_installation(), "U1")
  end

  test "list_thread_messages/3 issues conversations.replies with channel + ts" do
    stub(Req, :get, fn url, opts ->
      assert url == "https://slack.com/api/conversations.replies"
      assert Keyword.fetch!(opts, :params) == %{"channel" => "C1", "ts" => "1.0"}

      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "messages" => []}}}
    end)

    assert {:ok, %{"messages" => []}} =
             API.list_thread_messages(connected_installation(), "C1", "1.0")
  end

  test "decodes Slack ok: false as an error tuple" do
    stub(Req, :post, fn _url, _opts ->
      {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "channel_not_found"}}}
    end)

    assert {:error, {:slack_api_error, "channel_not_found"}} =
             API.post_message(connected_installation(), %{"channel" => "C1", "text" => "hi"})
  end

  test "short-circuits to :installation_disconnected for disconnected workspaces" do
    assert {:error, :installation_disconnected} =
             API.post_message(disconnected_installation(), %{"channel" => "C1"})
  end

  test "post_response/2 posts JSON to a response_url" do
    stub(Req, :post, fn url, opts ->
      assert url == "https://hooks.slack.com/something"
      assert Keyword.fetch!(opts, :json) == %{"text" => "ok"}

      {:ok, %Req.Response{status: 200, body: ""}}
    end)

    assert :ok = API.post_response("https://hooks.slack.com/something", %{"text" => "ok"})
  end
end
