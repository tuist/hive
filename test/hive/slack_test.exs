defmodule Hive.SlackTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Slack
  alias Hive.Slack.Channel
  alias Hive.Slack.Installation
  alias Hive.Slack.NotificationRoute
  alias Hive.Slack.User, as: SlackUser

  defp installation!(attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          team_id: "T#{suffix}",
          team_name: "Workspace #{suffix}",
          bot_user_id: "U#{suffix}",
          bot_token: "xoxb-#{suffix}",
          scope: "chat:write",
          installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        attrs
      )

    {:ok, installation} =
      %Installation{} |> Installation.changeset(attrs) |> Repo.insert()

    installation
  end

  describe "enabled?/0" do
    test "is true when all three Slack environment variables are set" do
      config = [
        client_id: "id",
        client_secret: "secret",
        signing_secret: "sign",
        allowed_team_ids: " T1, T2 ,T1"
      ]

      assert %{client_id: "id", allowed_team_ids: ["T1", "T2"]} = Slack.config(config)
    end

    test "is false when any Slack environment variable is missing or blank" do
      assert is_nil(Slack.config(client_id: "id", client_secret: "secret"))
      assert is_nil(Slack.config(client_id: "", client_secret: "s", signing_secret: "x"))
      assert is_nil(Slack.config([]))
    end
  end

  describe "default_bot_scopes/0" do
    test "returns the documented set of scopes" do
      scopes = Slack.default_bot_scopes()
      assert "app_mentions:read" in scopes
      assert "channels:history" in scopes
      assert "chat:write" in scopes
      assert "commands" in scopes
      assert "groups:history" in scopes
      assert "im:history" in scopes
      assert "mpim:history" in scopes
      assert "users:read.email" in scopes
    end
  end

  describe "find_active_installation_by_team_id/1" do
    test "returns the installation when it is connected" do
      installation = installation!()

      assert %Installation{id: id} =
               Slack.find_active_installation_by_team_id(installation.team_id)

      assert id == installation.id
    end

    test "returns nil for disconnected installations" do
      installation =
        installation!(%{
          bot_token: nil,
          disconnected_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      assert is_nil(Slack.find_active_installation_by_team_id(installation.team_id))
    end

    test "returns nil when no installation exists" do
      assert is_nil(Slack.find_active_installation_by_team_id("T-missing"))
    end
  end

  describe "notification settings" do
    test "updates notification routes by object type" do
      installation = installation!()

      assert {:ok, updated} =
               Slack.update_notification_routes(installation, %{
                 "notification_routes" => %{
                   "specs" => %{"slack_channel_id" => " C123 "}
                 }
               })

      assert %NotificationRoute{
               slack_channel_id: "C123",
               notification_events: [
                 "spec.created",
                 "spec.comment.created",
                 "spec.review.requested"
               ]
             } = Slack.notification_route_for(updated, "specs")
    end

    test "deletes notification routes when the channel is blank" do
      installation = installation!()

      assert {:ok, _updated} =
               Slack.update_notification_routes(installation, %{
                 "notification_routes" => %{
                   "specs" => %{"slack_channel_id" => "C123"}
                 }
               })

      assert {:ok, updated} =
               Slack.update_notification_routes(installation, %{
                 "notification_routes" => %{
                   "specs" => %{"slack_channel_id" => ""}
                 }
               })

      assert Slack.notification_route_for(updated, "specs").slack_channel_id == ""
    end

    test "lists connected notification targets from routes" do
      matching = installation!()
      other = installation!()

      assert {:ok, _updated} =
               Slack.update_notification_routes(matching, %{
                 "notification_routes" => %{
                   "specs" => %{"slack_channel_id" => "C-route"}
                 }
               })

      assert {:ok, _updated} =
               Slack.update_notification_routes(other, %{
                 "notification_routes" => %{
                   "specs" => %{"slack_channel_id" => ""}
                 }
               })

      assert [%Installation{id: id, notification_channel_id: "C-route"}] =
               Slack.notification_targets_for("spec.review.requested")

      assert id == matching.id
    end

    test "updates the notification channel and selected events" do
      installation = installation!()

      assert {:ok, updated} =
               Slack.update_notification_settings(installation, %{
                 "notification_channel_id" => " C123 ",
                 "notification_events" => ["", "spec.created"]
               })

      assert updated.notification_channel_id == "C123"
      assert updated.notification_events == ["spec.created"]
    end

    test "rejects unsupported notification events" do
      installation = installation!()
      events = Slack.notification_events()

      assert {:error, changeset} =
               Slack.update_notification_settings(installation, %{
                 "notification_channel_id" => "C123",
                 "notification_events" => ["unknown.event"]
               })

      assert {"has an invalid entry", [validation: :subset, enum: ^events]} =
               changeset.errors[:notification_events]
    end

    test "lists connected notification targets for an event" do
      matching =
        installation!(%{
          notification_channel_id: "C1",
          notification_events: ["spec.created"]
        })

      installation!(%{
        notification_channel_id: "C2",
        notification_events: ["spec.comment.created"]
      })

      installation!(%{
        notification_channel_id: "C3",
        notification_events: ["spec.created"],
        bot_token: nil,
        disconnected_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      assert [%Installation{id: id}] = Slack.notification_targets_for("spec.created")
      assert id == matching.id
    end

    test "defaults an empty event list to all notification events" do
      installation = installation!(%{notification_channel_id: "C1", notification_events: []})

      assert [%Installation{id: id}] = Slack.notification_targets_for("spec.comment.created")
      assert id == installation.id
    end
  end

  describe "upsert_channel/2" do
    test "inserts a channel and reuses the row on subsequent upserts" do
      installation = installation!()

      {:ok, channel} =
        Slack.upsert_channel(installation, %{slack_channel_id: "C123", name: "general"})

      assert channel.installation_id == installation.id
      assert channel.name == "general"

      {:ok, same} =
        Slack.upsert_channel(installation, %{slack_channel_id: "C123", name: "general-renamed"})

      assert same.id == channel.id
      assert same.name == "general-renamed"
      assert [%Channel{id: id}] = Repo.all(Channel)
      assert id == channel.id
    end
  end

  describe "upsert_user/2" do
    test "links to a Hive user with matching email" do
      installation = installation!()

      {:ok, hive_user} =
        Accounts.upsert_from_auth(%{
          email: "alice@example.com",
          provider: "test",
          provider_uid: "alice"
        })

      {:ok, slack_user} =
        Slack.upsert_user(installation, %{
          slack_user_id: "U1",
          email: "alice@example.com",
          name: "alice"
        })

      assert slack_user.linked_user_id == hive_user.id
    end

    test "leaves linked_user_id nil when no Hive user matches" do
      installation = installation!()

      {:ok, slack_user} =
        Slack.upsert_user(installation, %{
          slack_user_id: "U1",
          email: "noone@example.com"
        })

      assert is_nil(slack_user.linked_user_id)
      assert [%SlackUser{}] = Repo.all(SlackUser)
    end

    test "loads linked profiles by Hive user id for one workspace" do
      installation = installation!()
      other_installation = installation!()

      {:ok, hive_user} =
        Accounts.upsert_from_auth(%{
          email: "alice@example.com",
          provider: "test",
          provider_uid: "alice"
        })

      {:ok, slack_user} =
        Slack.upsert_user(installation, %{
          slack_user_id: "U1",
          email: "alice@example.com"
        })

      {:ok, _other_slack_user} =
        Slack.upsert_user(other_installation, %{
          slack_user_id: "U2",
          email: "alice@example.com"
        })

      user_id = hive_user.id

      assert %{^user_id => %{id: id, slack_user_id: "U1"}} =
               Slack.linked_user_profiles_by_user_ids(installation, [hive_user.id])

      assert id == slack_user.id
    end
  end

  describe "profile_authorize_url/3" do
    test "builds the Slack OpenID authorize URL" do
      assert {:ok, url} =
               Slack.profile_authorize_url(
                 "https://hive.example/account/slack/callback",
                 "state-1",
                 config: %{client_id: "client-id"}
               )

      assert url =~ "https://slack.com/openid/connect/authorize?"
      assert url =~ "client_id=client-id"
      assert url =~ "scope=openid+profile+email"
      assert url =~ "response_type=code"
      assert url =~ "state=state-1"
    end

    test "passes a Slack team hint when exactly one workspace is allowed" do
      assert {:ok, url} =
               Slack.profile_authorize_url(
                 "https://hive.example/account/slack/callback",
                 "state-1",
                 config: %{client_id: "client-id", allowed_team_ids: ["T-allowed"]}
               )

      assert url =~ "team=T-allowed"
    end

    test "does not pass a Slack team hint when multiple workspaces are allowed" do
      assert {:ok, url} =
               Slack.profile_authorize_url(
                 "https://hive.example/account/slack/callback",
                 "state-1",
                 config: %{client_id: "client-id", allowed_team_ids: ["T1", "T2"]}
               )

      refute url =~ "team="
    end

    test "still accepts the legacy direct config map" do
      assert {:ok, url} =
               Slack.profile_authorize_url(
                 "https://hive.example/account/slack/callback",
                 "state-1",
                 %{client_id: "client-id", allowed_team_ids: ["T-allowed"]}
               )

      assert url =~ "team=T-allowed"
    end
  end

  describe "complete_profile_link/4" do
    test "links the signed-in Hive user to the Slack profile even when emails differ" do
      installation = installation!(%{team_id: "T-openid", team_name: "Workspace"})

      {:ok, hive_user} =
        Accounts.upsert_from_auth(%{
          email: "hive@example.com",
          provider: "test",
          provider_uid: "hive@example.com"
        })

      stub(Req, :post, fn url, opts ->
        assert url == "https://slack.com/api/openid.connect.token"
        assert Keyword.fetch!(opts, :auth) == {:basic, "client-id:client-secret"}
        assert Keyword.fetch!(opts, :body) =~ "code=code-1"

        {:ok, %Req.Response{status: 200, body: %{"ok" => true, "access_token" => "xoxp-user"}}}
      end)

      stub(Req, :get, fn url, opts ->
        assert url == "https://slack.com/api/openid.connect.userInfo"
        assert {"authorization", "Bearer xoxp-user"} in Keyword.fetch!(opts, :headers)

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "https://slack.com/team_id" => installation.team_id,
             "https://slack.com/user_id" => "U-openid",
             "email" => "slack@example.com",
             "name" => "Slack User"
           }
         }}
      end)

      assert {:ok, slack_user} =
               Slack.complete_profile_link(
                 "code-1",
                 "https://hive.example/account/slack/callback",
                 hive_user,
                 config: %{client_id: "client-id", client_secret: "client-secret"}
               )

      assert slack_user.slack_user_id == "U-openid"
      assert slack_user.email == "slack@example.com"
      assert slack_user.linked_user_id == hive_user.id
    end

    test "requires the Slack workspace to be installed" do
      {:ok, hive_user} =
        Accounts.upsert_from_auth(%{
          email: "hive-missing@example.com",
          provider: "test",
          provider_uid: "hive-missing@example.com"
        })

      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => true, "access_token" => "xoxp-user"}}}
      end)

      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "https://slack.com/team_id" => "T-missing",
             "https://slack.com/user_id" => "U-openid"
           }
         }}
      end)

      assert {:error, :workspace_not_installed} =
               Slack.complete_profile_link(
                 "code-1",
                 "https://hive.example/account/slack/callback",
                 hive_user,
                 config: %{client_id: "client-id", client_secret: "client-secret"}
               )
    end

    test "rejects profiles from Slack workspaces outside the allowlist" do
      {:ok, hive_user} =
        Accounts.upsert_from_auth(%{
          email: "hive-disallowed@example.com",
          provider: "test",
          provider_uid: "hive-disallowed@example.com"
        })

      stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 200, body: %{"ok" => true, "access_token" => "xoxp-user"}}}
      end)

      stub(Req, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "ok" => true,
             "https://slack.com/team_id" => "T-disallowed",
             "https://slack.com/user_id" => "U-openid"
           }
         }}
      end)

      assert {:error, :workspace_not_allowed} =
               Slack.complete_profile_link(
                 "code-1",
                 "https://hive.example/account/slack/callback",
                 hive_user,
                 config: %{
                   client_id: "client-id",
                   client_secret: "client-secret",
                   allowed_team_ids: ["T-allowed"]
                 }
               )
    end
  end

  describe "insert_message/3" do
    test "inserts a message and is idempotent on (channel_id, slack_ts)" do
      installation = installation!()
      {:ok, channel} = Slack.upsert_channel(installation, %{slack_channel_id: "C1"})

      attrs = %{slack_ts: "1.2", text: "hi", raw_payload: %{}}

      {:ok, message} = Slack.insert_message(installation, channel, attrs)
      {:ok, same} = Slack.insert_message(installation, channel, attrs)

      assert message.id == same.id
    end
  end
end
