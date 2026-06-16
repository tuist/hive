defmodule HiveWeb.SlackControllerTest do
  use HiveWeb.ConnCase, async: true
  use Mimic

  alias Hive.Repo
  alias Hive.Slack.Installation
  alias Hive.Slack.Signature

  @secret "shhh"

  defp installation! do
    suffix = System.unique_integer([:positive])

    {:ok, installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{suffix}",
        team_name: "Workspace #{suffix}",
        bot_token: "xoxb-#{suffix}",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    installation
  end

  defp post_signed(conn, path, body) do
    timestamp = Integer.to_string(System.system_time(:second))

    signature =
      "v0=" <>
        (:hmac
         |> :crypto.mac(:sha256, @secret, "v0:" <> timestamp <> ":" <> body)
         |> Base.encode16(case: :lower))

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-slack-signature", signature)
    |> put_req_header("x-slack-request-timestamp", timestamp)
    |> post(path, body)
  end

  describe "POST /api/slack/events" do
    test "echoes a url_verification challenge", %{conn: conn} do
      stub(Signature, :secret, fn -> {:ok, @secret} end)

      body = Jason.encode!(%{"type" => "url_verification", "challenge" => "abc123"})
      conn = post_signed(conn, ~p"/api/slack/events", body)

      assert response(conn, 200) == "abc123"
    end

    test "200s when the signature is valid and the team is unknown", %{conn: conn} do
      stub(Signature, :secret, fn -> {:ok, @secret} end)

      body =
        Jason.encode!(%{
          "type" => "event_callback",
          "team_id" => "T-unknown",
          "event" => %{"type" => "app_mention"}
        })

      conn = post_signed(conn, ~p"/api/slack/events", body)
      assert response(conn, 200) == ""
    end

    test "200s for an event_callback targeting a known installation", %{conn: conn} do
      installation = installation!()
      stub(Signature, :secret, fn -> {:ok, @secret} end)
      stub(Hive.Agents, :enabled?, fn -> false end)

      body =
        Jason.encode!(%{
          "type" => "event_callback",
          "team_id" => installation.team_id,
          "event" => %{
            "type" => "app_mention",
            "channel" => "C-1",
            "user" => "U-1",
            "ts" => "1.0",
            "text" => "hi"
          }
        })

      conn = post_signed(conn, ~p"/api/slack/events", body)
      assert response(conn, 200) == ""
    end

    test "401s when the signature is invalid", %{conn: conn} do
      stub(Signature, :secret, fn -> {:ok, @secret} end)

      body = Jason.encode!(%{"type" => "url_verification", "challenge" => "abc"})

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-slack-signature", "v0=" <> String.duplicate("a", 64))
        |> put_req_header("x-slack-request-timestamp", "1")
        |> post(~p"/api/slack/events", body)

      assert response(conn, 401) == ""
    end

    test "503s when the signing secret is not configured", %{conn: conn} do
      stub(Signature, :secret, fn -> {:error, :not_configured} end)

      body = Jason.encode!(%{"type" => "url_verification", "challenge" => "abc"})
      conn = post_signed(conn, ~p"/api/slack/events", body)
      assert response(conn, 503) == ""
    end
  end

  describe "POST /api/slack/interactions" do
    test "accepts a payload= form body and 200s", %{conn: conn} do
      installation = installation!()
      stub(Signature, :secret, fn -> {:ok, @secret} end)

      payload = %{
        "type" => "block_actions",
        "team" => %{"id" => installation.team_id},
        "user" => %{"id" => "U-1"}
      }

      body = "payload=" <> URI.encode_www_form(Jason.encode!(payload))

      timestamp = Integer.to_string(System.system_time(:second))

      signature =
        "v0=" <>
          (:hmac
           |> :crypto.mac(:sha256, @secret, "v0:" <> timestamp <> ":" <> body)
           |> Base.encode16(case: :lower))

      conn =
        conn
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("x-slack-signature", signature)
        |> put_req_header("x-slack-request-timestamp", timestamp)
        |> post(~p"/api/slack/interactions", body)

      assert response(conn, 200) == ""
    end
  end
end
