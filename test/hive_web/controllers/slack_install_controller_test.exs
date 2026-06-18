defmodule HiveWeb.SlackInstallControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Slack.Installation
  alias Hive.Slack.Installations

  describe "GET /slack/install" do
    test "redirects anonymous users to login even when the instance is public", %{conn: conn} do
      stub(Hive.Slack, :enabled?, fn -> true end)

      conn = get(conn, ~p"/slack/install")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Log in"
    end

    test "redirects non-admins away from workspace management", %{conn: conn} do
      {conn, user} = sign_in(conn, "member@example.com")
      {:ok, _user} = Accounts.update_user_role(user, :member)

      conn = get(conn, ~p"/slack/install")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "instance admins"
    end

    test "redirects to the Slack authorize URL with a signed state token", %{conn: conn} do
      stub(Installations, :authorize_url, fn _redirect, state, _conf ->
        send(self(), {:state, state})
        {:ok, "https://slack.com/oauth/v2/authorize?state=" <> state}
      end)

      stub(Hive.Slack, :enabled?, fn -> true end)

      {conn, user} = sign_in(conn, "admin@example.com")
      {:ok, user} = Accounts.update_user_role(user, :admin)
      conn = get(conn, ~p"/slack/install")

      assert redirected_to(conn) =~ "https://slack.com/oauth/v2/authorize?state="
      assert_receive {:state, state}
      assert is_binary(state) and byte_size(state) > 0

      assert {:ok, %{user_id: user_id}} =
               Phoenix.Token.verify(HiveWeb.Endpoint, "slack_install", state)

      assert user_id == user.id
    end

    test "redirects to /ops/slack with a flash when Slack isn't configured", %{conn: conn} do
      stub(Hive.Slack, :enabled?, fn -> false end)

      {conn, user} = sign_in(conn, "admin-unconfigured@example.com")
      {:ok, _user} = Accounts.update_user_role(user, :admin)
      conn = get(conn, ~p"/slack/install")

      assert redirected_to(conn) == ~p"/ops/slack"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "isn't configured"
    end
  end

  describe "GET /slack/install/callback" do
    test "rejects requests with a mismatched state", %{conn: conn} do
      {conn, user} = sign_in(conn, "admin-callback-mismatch@example.com")
      {:ok, _user} = Accounts.update_user_role(user, :admin)
      conn = get(conn, ~p"/slack/install/callback?state=other&code=abc")

      assert redirected_to(conn) == ~p"/ops/slack"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
    end

    test "surfaces Slack callback errors", %{conn: conn} do
      {conn, user} = sign_in(conn, "admin-callback-error@example.com")
      {:ok, user} = Accounts.update_user_role(user, :admin)
      state = slack_install_state(conn, user)

      conn =
        get(
          conn,
          ~p"/slack/install/callback?state=#{state}&error=invalid_team_for_non_distributed_app"
        )

      assert redirected_to(conn) == ~p"/ops/slack"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Slack rejected the install: invalid team for non distributed app."
    end

    test "completes the install when state matches", %{conn: conn} do
      stub(Installations, :complete_install, fn "code-1", _redirect_uri, opts ->
        assert is_binary(opts[:installed_by_user_id])

        {:ok,
         %Installation{
           id: Ecto.UUID.generate(),
           team_id: "T1",
           team_name: "Workspace"
         }}
      end)

      {conn, user} = sign_in(conn, "admin-callback@example.com")
      {:ok, user} = Accounts.update_user_role(user, :admin)
      state = slack_install_state(conn, user)
      conn = get(conn, ~p"/slack/install/callback?state=#{state}&code=code-1")

      assert redirected_to(conn) == ~p"/ops/slack"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Workspace"
    end

    test "redirects anonymous callbacks to login", %{conn: conn} do
      conn = get(conn, ~p"/slack/install/callback?state=valid&code=code-1")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Log in"
    end
  end

  describe "POST /slack/installations/:id/disconnect" do
    test "redirects non-admins away from disconnecting workspaces", %{conn: conn} do
      {conn, user} = sign_in(conn, "member-disconnect@example.com")
      {:ok, _user} = Accounts.update_user_role(user, :member)

      conn = post(conn, ~p"/slack/installations/#{Ecto.UUID.generate()}/disconnect")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "instance admins"
    end
  end

  defp slack_install_state(_conn, user) do
    Phoenix.Token.sign(HiveWeb.Endpoint, "slack_install", %{nonce: "test", user_id: user.id})
  end
end
