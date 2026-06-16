defmodule Hive.Slack.InstallationsTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Slack.Installation
  alias Hive.Slack.Installations

  @config %{
    client_id: "client-id",
    client_secret: "client-secret",
    signing_secret: "signing-secret",
    scopes: ["chat:write"]
  }

  describe "authorize_url/3" do
    test "builds the Slack authorize URL with scopes joined by comma" do
      assert {:ok, url} =
               Installations.authorize_url(
                 "https://hive.example/slack/install/callback",
                 "abc",
                 @config
               )

      assert url =~ "https://slack.com/oauth/v2/authorize?"
      assert url =~ "client_id=client-id"
      assert url =~ "scope=chat%3Awrite"
      assert url =~ "state=abc"
      assert url =~ "redirect_uri=https%3A%2F%2Fhive.example%2Fslack%2Finstall%2Fcallback"
    end

    test "returns :not_configured when no config is set" do
      assert {:error, :not_configured} =
               Installations.authorize_url("https://example", "abc", nil)
    end
  end

  describe "complete_install/3" do
    test "exchanges the code, inserts an installation, and records an audit entry" do
      stub(Req, :post, fn url, opts ->
        assert url == "https://slack.com/api/oauth.v2.access"
        assert {:basic, "client-id:client-secret"} = Keyword.fetch!(opts, :auth)
        body = Keyword.fetch!(opts, :body)
        assert body =~ "code=auth-code"
        assert body =~ "redirect_uri=https%3A%2F%2Fhive.example%2Fslack%2Finstall%2Fcallback"

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-fresh",
             "scope" => "chat:write,app_mentions:read",
             "bot_user_id" => "U-bot",
             "team" => %{"id" => "T1", "name" => "Workspace"}
           }
         }}
      end)

      assert {:ok, %Installation{} = installation} =
               Installations.complete_install(
                 "auth-code",
                 "https://hive.example/slack/install/callback",
                 config: @config
               )

      assert installation.team_id == "T1"
      assert installation.team_name == "Workspace"
      assert installation.bot_token == "xoxb-fresh"
      assert installation.bot_user_id == "U-bot"
      assert Installation.connected?(installation)
    end

    test "upserts by team_id when the workspace re-installs" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-second",
             "team" => %{"id" => "T1", "name" => "Workspace renamed"}
           }
         }}
      end)

      {:ok, first} =
        Installations.complete_install("code1", "https://hive.example/slack/install/callback",
          config: @config
        )

      {:ok, second} =
        Installations.complete_install("code2", "https://hive.example/slack/install/callback",
          config: @config
        )

      assert second.id == first.id
      assert second.team_name == "Workspace renamed"
      assert second.bot_token == "xoxb-second"
    end

    test "returns an error when Slack responds with ok: false" do
      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => false, "error" => "invalid_code"}}}
      end)

      assert {:error, {:slack_oauth_error, "invalid_code"}} =
               Installations.complete_install("bad", "https://example", config: @config)
    end

    test "returns an error when called without config" do
      assert {:error, :not_configured} =
               Installations.complete_install("x", "https://example", config: nil)
    end
  end

  describe "disconnect/1" do
    test "nulls the bot_token and stamps disconnected_at" do
      stub(Req, :post, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "access_token" => "xoxb-fresh",
             "team" => %{"id" => "T1", "name" => "Workspace"}
           }
         }}
      end)

      {:ok, installation} =
        Installations.complete_install("code", "https://example", config: @config)

      assert {:ok, disconnected} = Installations.disconnect(installation)

      assert is_nil(disconnected.bot_token)
      refute is_nil(disconnected.disconnected_at)
      refute Installation.connected?(disconnected)
    end
  end
end
