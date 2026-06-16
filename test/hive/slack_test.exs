defmodule Hive.SlackTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Slack
  alias Hive.Slack.Channel
  alias Hive.Slack.Installation
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
    test "is true when all three Slack env vars are set" do
      config = [client_id: "id", client_secret: "secret", signing_secret: "sign"]
      assert %{client_id: "id"} = Slack.config(config)
    end

    test "is false when any Slack env var is missing or blank" do
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
