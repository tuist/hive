defmodule HiveWeb.SlackProfileControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Slack.User, as: SlackUser

  describe "GET /account/slack/new" do
    test "redirects anonymous users to login", %{conn: conn} do
      conn = get(conn, ~p"/account/slack/new")

      assert redirected_to(conn) == ~p"/login?return_to=/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Log in"
    end

    test "redirects to Slack OpenID authorize URL", %{conn: conn} do
      stub(Hive.Slack, :enabled?, fn -> true end)

      stub(Hive.Slack, :profile_authorize_url, fn _redirect_uri, state, _conf ->
        send(self(), {:state, state})
        {:ok, "https://slack.com/openid/connect/authorize?state=" <> state}
      end)

      {conn, user} = sign_in(conn, "alice-slack-link@example.com")
      conn = get(conn, ~p"/account/slack/new")

      assert redirected_to(conn) =~ "https://slack.com/openid/connect/authorize?state="
      assert_receive {:state, state}

      assert {:ok, %{user_id: user_id}} =
               Phoenix.Token.verify(HiveWeb.Endpoint, "slack_profile", state)

      assert user_id == user.id
    end

    test "redirects to account settings when Slack is not configured", %{conn: conn} do
      stub(Hive.Slack, :enabled?, fn -> false end)

      {conn, _user} = sign_in(conn, "alice-slack-unconfigured@example.com")
      conn = get(conn, ~p"/account/slack/new")

      assert redirected_to(conn) == ~p"/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "isn't configured"
    end
  end

  describe "GET /account/slack/callback" do
    test "rejects mismatched state", %{conn: conn} do
      {conn, _user} = sign_in(conn, "alice-slack-mismatch@example.com")
      conn = get(conn, ~p"/account/slack/callback?state=other&code=abc")

      assert redirected_to(conn) == ~p"/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end

    test "completes the profile link", %{conn: conn} do
      {conn, user} = sign_in(conn, "alice-slack-callback@example.com")
      state = slack_profile_state(user)

      stub(Hive.Slack, :complete_profile_link, fn "code-1", _redirect_uri, ^user ->
        {:ok, %SlackUser{slack_user_id: "U1"}}
      end)

      conn = get(conn, ~p"/account/slack/callback?state=#{state}&code=code-1")

      assert redirected_to(conn) == ~p"/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "U1"
    end

    test "reports uninstalled workspaces", %{conn: conn} do
      {conn, user} = sign_in(conn, "alice-slack-missing-workspace@example.com")
      state = slack_profile_state(user)

      stub(Hive.Slack, :complete_profile_link, fn "code-1", _redirect_uri, ^user ->
        {:error, :workspace_not_installed}
      end)

      conn = get(conn, ~p"/account/slack/callback?state=#{state}&code=code-1")

      assert redirected_to(conn) == ~p"/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "workspace is not connected"
    end

    test "reports workspaces outside the allowlist", %{conn: conn} do
      {conn, user} = sign_in(conn, "alice-slack-disallowed-workspace@example.com")
      state = slack_profile_state(user)

      stub(Hive.Slack, :complete_profile_link, fn "code-1", _redirect_uri, ^user ->
        {:error, :workspace_not_allowed}
      end)

      conn = get(conn, ~p"/account/slack/callback?state=#{state}&code=code-1")

      assert redirected_to(conn) == ~p"/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not allowed"
    end
  end

  defp slack_profile_state(user) do
    Phoenix.Token.sign(HiveWeb.Endpoint, "slack_profile", %{nonce: "test", user_id: user.id})
  end
end
