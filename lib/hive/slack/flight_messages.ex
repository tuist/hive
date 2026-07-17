defmodule Hive.Slack.FlightMessages do
  @moduledoc false

  alias Hive.Flights
  alias Hive.Flights.Flight
  alias Hive.Slack
  alias Hive.Slack.API

  def update(%Flight{trigger: trigger} = flight) do
    with %{
           "installation_id" => installation_id,
           "channel_id" => channel_id,
           "message_ts" => message_ts
         } <- trigger,
         installation when not is_nil(installation) <- Slack.get_installation(installation_id),
         {:ok, _response} <-
           API.update_message(installation, %{
             "channel" => channel_id,
             "ts" => message_ts,
             "text" => message(flight)
           }) do
      :ok
    else
      %{} -> :ok
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp message(%Flight{} = flight) do
    label = Flights.objective_label(flight.objective)
    flight_url = HiveWeb.Endpoint.url() <> Flights.path(flight)
    title = flight.input["title"] || "Forage item"

    "#{status_prefix(flight)} *#{label} Flight #{status_word(flight)}* for #{forage_link(flight, title)} in `#{flight.repository_full_name}`.#{result_suffix(flight)} <#{flight_url}|View Flight>"
  end

  defp forage_link(%Flight{forage_item_id: forage_item_id}, title) do
    case Flights.forage_item_path(%{id: forage_item_id}) do
      nil -> title
      path -> "<#{HiveWeb.Endpoint.url()}#{path}|#{title}>"
    end
  end

  defp status_prefix(%Flight{status: :queued}), do: ":hourglass_flowing_sand:"
  defp status_prefix(%Flight{status: :running}), do: ":mag:"
  defp status_prefix(%Flight{status: :succeeded}), do: ":white_check_mark:"
  defp status_prefix(%Flight{status: :failed}), do: ":x:"

  defp status_word(%Flight{status: :queued}), do: "queued"
  defp status_word(%Flight{status: :running}), do: "running"
  defp status_word(%Flight{status: :succeeded}), do: "completed"
  defp status_word(%Flight{status: :failed}), do: "failed"

  defp result_suffix(%Flight{status: :succeeded, objective_outcome: outcome, result: result}) do
    outcome = Flights.objective_outcome_label(outcome)
    summary = result && result["summary"]

    [outcome, summary]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(": ")
    |> case do
      "" -> ""
      text -> " #{text}."
    end
  end

  defp result_suffix(%Flight{status: :failed, error: error}) when is_binary(error),
    do: " #{error}."

  defp result_suffix(_flight), do: ""
end
