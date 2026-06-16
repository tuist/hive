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

    test "redirects collaborators away from workspace management", %{conn: conn} do
      {conn, user} = sign_in(conn, "collaborator@example.com")
      {:ok, _user} = Accounts.update_user_role(user, :collaborator)

      conn = get(conn, ~p"/slack/install")

      assert redirected_to(conn) == ~p"/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "organization members"
    end

    test "redirects to the Slack authorize URL with a state cookie", %{conn: conn} do
      stub(Installations, :authorize_url, fn _redirect, state, _conf ->
        send(self(), {:state, state})
        {:ok, "https://slack.com/oauth/v2/authorize?state=" <> state}
      end)

      stub(Hive.Slack, :enabled?, fn -> true end)

      {conn, _user} = sign_in(conn, "alice@example.com")
      conn = get(conn, ~p"/slack/install")

      assert redirected_to(conn) =~ "https://slack.com/oauth/v2/authorize?state="
      assert_receive {:state, state}
      assert is_binary(state) and byte_size(state) > 0
    end

    test "redirects to /account/slack with a flash when Slack isn't configured", %{conn: conn} do
      stub(Hive.Slack, :enabled?, fn -> false end)

      {conn, _user} = sign_in(conn, "alice@example.com")
      conn = get(conn, ~p"/slack/install")

      assert redirected_to(conn) == ~p"/account/slack"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "isn't configured"
    end
  end

  describe "GET /slack/install/callback" do
    test "rejects requests with a mismatched state", %{conn: conn} do
      {conn, _user} = sign_in(conn, "alice@example.com")

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          user_id: get_session(conn, :user_id),
          slack_install_state: "expected"
        })
        |> get(~p"/slack/install/callback?state=other&code=abc")

      assert redirected_to(conn) == ~p"/account/slack"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
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

      {conn, _user} = sign_in(conn, "alice@example.com")

      conn =
        conn
        |> Plug.Test.init_test_session(%{
          user_id: get_session(conn, :user_id),
          slack_install_state: "valid"
        })
        |> get(~p"/slack/install/callback?state=valid&code=code-1")

      assert redirected_to(conn) == ~p"/account/slack"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Workspace"
    end

    test "redirects anonymous callbacks to login", %{conn: conn} do
      conn = get(conn, ~p"/slack/install/callback?state=valid&code=code-1")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Log in"
    end
  end

  describe "POST /slack/installations/:id/disconnect" do
    test "redirects collaborators away from disconnecting workspaces", %{conn: conn} do
      {conn, user} = sign_in(conn, "collaborator-disconnect@example.com")
      {:ok, _user} = Accounts.update_user_role(user, :collaborator)

      conn = post(conn, ~p"/slack/installations/#{Ecto.UUID.generate()}/disconnect")

      assert redirected_to(conn) == ~p"/account/identities"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "organization members"
    end
  end
end
