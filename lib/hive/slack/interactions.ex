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

  alias Hive.Audit
  alias Hive.Forage.Intake
  alias Hive.Slack
  alias Hive.Slack.API
  alias Hive.Slack.Installation

  @forage_item_callback_id "capture_forage_item"
  @feature_request_callback_id "capture_feature_request"

  @doc """
  Handles a verified interaction payload for a known installation.
  """
  def handle(%{"type" => "message_action"} = payload, %Installation{} = installation) do
    case payload["callback_id"] do
      @forage_item_callback_id -> capture_forage_item(payload, installation)
      @feature_request_callback_id -> capture_forage_item(payload, installation)
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

  defp capture_forage_item(payload, installation) do
    slack_user_id = get_in(payload, ["user", "id"])
    response_url = payload["response_url"]
    message_text = get_in(payload, ["message", "text"]) || ""
    permalink = build_permalink(installation, payload)

    case Slack.resolve_hive_user(installation, slack_user_id) do
      {:ok, user} ->
        title = derive_title(message_text)
        description = derive_description(message_text)

        case Intake.create(
               %{
                 "type" => "feature_request",
                 "title" => title,
                 "description" => description,
                 "source_label" => "Slack message",
                 "source_url" => permalink
               },
               user,
               interface: "webhook"
             ) do
          {:ok, result} ->
            Audit.record("slack.forage_item.captured", %{
              actor: user,
              interface: "webhook",
              target_type: result.target_type,
              target_id: result.target_id,
              target_label: result.target_label,
              metadata: %{
                destination: Atom.to_string(result.destination),
                external_url: result.external_url,
                path: result.hive_path,
                team_id: installation.team_id,
                slack_user_id: slack_user_id,
                slack_message_permalink: permalink
              }
            })

            respond(
              response_url,
              capture_success_message(result)
            )

          {:error, %Ecto.Changeset{}} ->
            respond(
              response_url,
              dgettext(
                "dashboard_slack",
                "I couldn't capture that message. Try rewording the description (it must be at least 10 characters)."
              )
            )

          {:error, :unauthorized} ->
            respond(
              response_url,
              dgettext("dashboard_slack", "You are not allowed to create forage items here.")
            )

          {:error, reason}
          when reason in [:github_repository_not_configured, :github_repository_not_found] ->
            respond(
              response_url,
              dgettext(
                "dashboard_slack",
                "I couldn't capture that message because the forage intake destination is not configured."
              )
            )

          {:error, _reason} ->
            respond(
              response_url,
              dgettext("dashboard_slack", "I couldn't capture that message.")
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

  defp capture_success_message(%Intake.Result{destination: :github_issue} = result) do
    dgettext(
      "dashboard_slack",
      "Created %{external_link} and added it to Hive forage: %{hive_link}.",
      external_link: slack_link(result.external_url, result.external_label || "GitHub issue"),
      hive_link: slack_link(hive_url(result.hive_path), dgettext("dashboard_slack", "view item"))
    )
  end

  defp capture_success_message(%Intake.Result{} = result) do
    dgettext("dashboard_slack", "Captured as a forage item in Hive: %{link}.",
      link: slack_link(hive_url(result.hive_path), dgettext("dashboard_slack", "view item"))
    )
  end

  defp slack_link(nil, label), do: label
  defp slack_link(url, label), do: "<#{url}|#{label}>"

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
