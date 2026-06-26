defmodule Hive.Slack.Interactions do
  @moduledoc """
  Dispatches Slack Block Kit and message shortcut interaction payloads.

  The controller verifies the signature, resolves the installation by
  `team.id`, and hands off the decoded payload here. Anything we want
  the invoking user to see goes back through the `response_url` (the
  HTTP response body is ignored by Slack for shortcuts).
  """

  use Gettext, backend: HiveWeb.Gettext

  require Logger

  alias Hive.Accounts
  alias Hive.Audit
  alias Hive.Forage
  alias Hive.Slack.API
  alias Hive.Slack.Installation

  @feature_request_callback_id "capture_feature_request"

  @doc """
  Handles a verified interaction payload for a known installation.
  """
  def handle(%{"type" => "message_action"} = payload, %Installation{} = installation) do
    case payload["callback_id"] do
      @feature_request_callback_id -> capture_feature_request(payload, installation)
      _other -> :ok
    end
  end

  def handle(%{"type" => "block_actions"}, %Installation{}), do: :ok
  def handle(%{"type" => "view_submission"}, %Installation{}), do: :ok
  def handle(%{"type" => "shortcut"}, %Installation{}), do: :ok

  def handle(payload, %Installation{}) do
    Logger.debug(fn -> "[Slack.Interactions] ignoring type: #{inspect(payload["type"])}" end)
    :ok
  end

  defp capture_feature_request(payload, installation) do
    slack_user_id = get_in(payload, ["user", "id"])
    response_url = payload["response_url"]
    message_text = get_in(payload, ["message", "text"]) || ""
    permalink = build_permalink(installation, payload)

    case resolve_hive_user(installation, slack_user_id) do
      {:ok, user} ->
        title = derive_title(message_text)
        description = derive_description(message_text)

        case Forage.create_feature_request(
               %{"title" => title, "description" => description},
               user
             ) do
          {:ok, feature_request} ->
            Audit.record("slack.feature_request.captured", %{
              actor: user,
              interface: "slack",
              target_type: "feature_request",
              target_id: feature_request.id,
              target_label: feature_request.title,
              metadata: %{
                team_id: installation.team_id,
                slack_user_id: slack_user_id,
                slack_message_permalink: permalink
              }
            })

            respond(
              response_url,
              dgettext("dashboard_slack", "Captured as a feature request in Hive: %{link}.",
                link:
                  "<#{hive_url("/forage?filter_type_op=%3D%3D&filter_type_val=feature_request")}|#{dgettext("dashboard_slack", "view forage")}>"
              )
            )

          {:error, _changeset} ->
            respond(
              response_url,
              dgettext(
                "dashboard_slack",
                "I couldn't capture that message. Try rewording the description (it must be at least 10 characters)."
              )
            )
        end

      {:error, :no_match} ->
        respond(
          response_url,
          dgettext(
            "dashboard_slack",
            "I couldn't match your Slack account to a Hive user. Sign in to Hive with your work email and try again."
          )
        )

      {:error, _other} ->
        respond(
          response_url,
          dgettext("dashboard_slack", "Something went wrong looking up your Hive account.")
        )
    end
  end

  defp resolve_hive_user(_installation, nil), do: {:error, :no_match}

  defp resolve_hive_user(installation, slack_user_id) do
    case API.get_user(installation, slack_user_id) do
      {:ok, %{"user" => %{"profile" => %{"email" => email}}}}
      when is_binary(email) and email != "" ->
        case Accounts.get_user_by_email(email) do
          nil -> {:error, :no_match}
          user -> {:ok, user}
        end

      {:ok, _other} ->
        {:error, :no_match}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp derive_title(text) do
    text
    |> String.split(~r/[\.\n!?]/, parts: 2)
    |> List.first()
    |> Kernel.||("")
    |> String.trim()
    |> case do
      "" -> dgettext("dashboard_slack", "Captured from Slack")
      first -> String.slice(first, 0, 160)
    end
  end

  defp derive_description(text) do
    text
    |> String.trim()
    |> case do
      "" -> dgettext("dashboard_slack", "(no message text)")
      trimmed -> String.slice(trimmed, 0, 2000)
    end
    |> ensure_min_length()
  end

  defp ensure_min_length(text) do
    if String.length(text) < 10 do
      dgettext("dashboard_slack", "%{text} (captured from Slack)", text: text)
    else
      text
    end
  end

  defp respond(nil, _text), do: :ok

  defp respond(response_url, text) when is_binary(response_url) do
    API.post_response(response_url, %{
      "response_type" => "ephemeral",
      "text" => text
    })
  end

  defp build_permalink(_installation, payload) do
    case payload do
      %{"message" => %{"permalink" => permalink}} when is_binary(permalink) -> permalink
      _ -> nil
    end
  end

  defp hive_url(path) do
    case Application.get_env(:hive, HiveWeb.Endpoint, []) |> get_in([:url]) do
      nil -> path
      url -> "#{url[:scheme] || "https"}://#{url[:host]}#{path}"
    end
  end
end
