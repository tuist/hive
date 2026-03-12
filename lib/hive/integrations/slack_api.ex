defmodule Hive.Integrations.SlackAPI do
  @moduledoc """
  Wraps Slack API calls needed during signal ingestion.
  """

  alias Hive.Integrations.SlackIntegration

  @slack_api_url "https://slack.com/api"

  def get_user_display_name(%SlackIntegration{} = integration, user_id) when is_binary(user_id) do
    case Req.get(
           "#{@slack_api_url}/users.info",
           auth: {:bearer, integration.bot_token},
           params: [user: user_id]
         ) do
      {:ok, %{status: 200, body: %{"ok" => true, "user" => user}}} ->
        {:ok, build_display_name(user, user_id)}

      {:ok, %{body: %{"ok" => false, "error" => error}}} ->
        {:error, error}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_display_name(user, fallback) do
    profile = user["profile"] || %{}

    [
      profile["display_name"],
      profile["real_name"],
      user["real_name"],
      user["name"],
      fallback
    ]
    |> Enum.find(fallback, &(is_binary(&1) && String.trim(&1) != ""))
  end
end
