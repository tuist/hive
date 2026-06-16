defmodule HiveWeb.SlackController do
  use HiveWeb, :controller

  require Logger

  alias Hive.Audit
  alias Hive.Slack
  alias Hive.Slack.Events
  alias Hive.Slack.Interactions
  alias Hive.Slack.Signature

  def events(conn, params) do
    with {:ok, raw_body} <- raw_body(conn),
         :ok <- verify(conn, raw_body) do
      handle_events_payload(conn, params)
    else
      {:error, :not_configured} ->
        send_resp(conn, :service_unavailable, "")

      {:error, _reason} ->
        send_resp(conn, :unauthorized, "")
    end
  end

  def interactions(conn, params) do
    with {:ok, raw_body} <- raw_body(conn),
         :ok <- verify(conn, raw_body),
         {:ok, payload} <- decode_interaction_payload(params) do
      put_slack_context(conn, payload)
      _ = dispatch_interaction(payload)
      send_resp(conn, :ok, "")
    else
      {:error, :not_configured} ->
        send_resp(conn, :service_unavailable, "")

      {:error, _reason} ->
        send_resp(conn, :unauthorized, "")
    end
  end

  defp handle_events_payload(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(:ok, challenge)
  end

  defp handle_events_payload(conn, %{"team_id" => team_id} = payload) when is_binary(team_id) do
    case Slack.find_active_installation_by_team_id(team_id) do
      nil ->
        Logger.info("[Slack.events] no active installation for team #{team_id}")
        send_resp(conn, :ok, "")

      installation ->
        put_slack_context_for_installation(installation)
        _ = Events.handle(payload, installation)
        send_resp(conn, :ok, "")
    end
  end

  defp handle_events_payload(conn, _payload), do: send_resp(conn, :ok, "")

  defp dispatch_interaction(payload) do
    team_id = get_in(payload, ["team", "id"])

    case Slack.find_active_installation_by_team_id(team_id) do
      nil ->
        Logger.info("[Slack.interactions] no active installation for team #{inspect(team_id)}")
        :ok

      installation ->
        put_slack_context_for_installation(installation)
        Interactions.handle(payload, installation)
    end
  end

  defp put_slack_context(_conn, payload) do
    team_id = get_in(payload, ["team", "id"]) || payload["team_id"]
    team_name = get_in(payload, ["team", "domain"]) || get_in(payload, ["team", "name"])

    Audit.put_context(%{
      interface: "slack",
      actor: Audit.agent_actor("slack"),
      target_label: team_name || team_id
    })
  end

  defp put_slack_context_for_installation(installation) do
    Audit.put_context(%{
      interface: "slack",
      actor: Audit.agent_actor("slack"),
      target_label: installation.team_name || installation.team_id
    })
  end

  defp decode_interaction_payload(%{"payload" => raw_payload}) when is_binary(raw_payload) do
    case Jason.decode(raw_payload) do
      {:ok, payload} -> {:ok, payload}
      {:error, _reason} -> {:error, :invalid_payload}
    end
  end

  defp decode_interaction_payload(_params), do: {:error, :invalid_payload}

  defp raw_body(conn) do
    case Map.get(conn.private, :hive_raw_body) do
      body when is_binary(body) -> {:ok, body}
      _ -> {:error, :missing_body}
    end
  end

  defp verify(conn, raw_body) do
    signature = conn |> get_req_header("x-slack-signature") |> List.first()
    timestamp = conn |> get_req_header("x-slack-request-timestamp") |> List.first()

    with {:ok, secret} <- Signature.secret() do
      Signature.verify(raw_body, signature || "", timestamp || "", secret)
    end
  end
end
