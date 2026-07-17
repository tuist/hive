defmodule Hive.Slack.FlightCommands do
  @moduledoc """
  Handles deterministic Flight commands from Slack alert threads.
  """

  alias Hive.Auth
  alias Hive.Domains.GitHubRepository
  alias Hive.Flights
  alias Hive.Forage
  alias Hive.Forage.CodingRuns
  alias Hive.Forage.Grafana
  alias Hive.Slack.API
  alias Hive.Slack.FlightMessages

  @flight_words ~r/\b(investigate|reproduce|repro|fix)\b/i
  @grafana_item_path ~r"/forage/items/grafana-alert/([0-9a-f-]{36})(?:\b|/)"i

  def handle(thread, requester, installation, channel_id, thread_ts) when is_list(thread) do
    triggering_message = Enum.find(thread, & &1["triggering_mention"])

    with %{"text" => text} <- triggering_message,
         {:ok, objective} <- parse(text) do
      start(objective, text, thread, requester, installation, channel_id, thread_ts)
    else
      :not_a_command -> :not_a_command
      nil -> :not_a_command
    end
  end

  def parse(text) when is_binary(text) do
    case Regex.run(@flight_words, text, capture: :all_but_first) do
      [word] when word in ["reproduce", "repro"] -> {:ok, :reproduce}
      ["fix"] -> {:ok, :fix}
      ["investigate"] -> {:ok, :investigate}
      [word] -> parse(String.downcase(word))
      nil -> :not_a_command
    end
  end

  def parse(_text), do: :not_a_command

  defp start(_objective, _text, _thread, requester, installation, channel_id, thread_ts)
       when is_nil(requester) do
    post_reply(
      installation,
      channel_id,
      thread_ts,
      "Link your Slack profile to a Hive account before starting a Flight."
    )
  end

  defp start(objective, text, thread, requester, installation, channel_id, thread_ts) do
    if Auth.member?(requester) do
      with {:ok, item} <- correlate_item(thread, requester),
           {:ok, repository} <- choose_repository(item, text),
           :ok <- ensure_no_active_flight(item, repository),
           {:ok, %{"ts" => message_ts}} <-
             post_starting(installation, channel_id, thread_ts, objective) do
        launch_flight(
          objective,
          item,
          repository,
          requester,
          installation,
          channel_id,
          thread_ts,
          message_ts
        )
      else
        {:error, reason} ->
          post_reply(installation, channel_id, thread_ts, failure_text(reason))
      end
    else
      post_reply(
        installation,
        channel_id,
        thread_ts,
        "Only organization members can start Flights."
      )
    end
  end

  defp launch_flight(
         objective,
         item,
         repository,
         requester,
         installation,
         channel_id,
         thread_ts,
         message_ts
       ) do
    trigger = %{
      "source" => "slack",
      "installation_id" => installation.id,
      "channel_id" => channel_id,
      "thread_ts" => thread_ts,
      "message_ts" => message_ts
    }

    case Flights.start_for_item(item, repository.id, requester,
           objective: objective,
           trigger: trigger
         ) do
      {:ok, flight} ->
        _ = FlightMessages.update(flight)
        {:handled, flight}

      {:error, reason} ->
        # The "Starting..." message was already posted, so update it in place to
        # the failure state instead of leaving it falsely stuck at "Starting".
        _ =
          API.update_message(installation, %{
            "channel" => channel_id,
            "ts" => message_ts,
            "text" => failure_text(reason)
          })

        {:handled, nil}
    end
  end

  defp failure_text(:alert_not_found),
    do:
      "I could not match this thread to a Grafana alert in Hive. Include the Hive Forage link or the original Grafana alert link."

  defp failure_text(:ambiguous_alert),
    do:
      "This thread refers to more than one Grafana alert. Include the Hive Forage link for the alert to use."

  defp failure_text({:choose_repository, repositories}) do
    choices = Enum.map_join(repositories, ", ", &"`#{&1}`")
    "Choose a repository by mentioning its full name: #{choices}."
  end

  defp failure_text(:repository_not_found),
    do: "No linked repository is available for this alert."

  defp failure_text(:already_running),
    do: "A Flight is already active for this alert and repository."

  defp failure_text({:active_flight, flight}),
    do:
      "A Flight is already active for this alert and repository. <#{HiveWeb.Endpoint.url()}#{Flights.path(flight)}|View Flight>"

  defp failure_text(:not_configured),
    do: "The Flight runner is not configured in Hive."

  defp failure_text(reason),
    do: "The Flight could not be started: `#{inspect(reason)}`."

  defp correlate_item(thread, requester) do
    urls = thread |> Enum.flat_map(&(&1["urls"] || [])) |> Enum.uniq()

    item_ids =
      Enum.flat_map(urls, fn url ->
        case Regex.run(@grafana_item_path, url, capture: :all_but_first) do
          [id] -> ["grafana_alert:#{id}"]
          nil -> []
        end
      end)

    items =
      item_ids
      |> Enum.uniq()
      |> Enum.flat_map(fn item_id ->
        case Forage.get_item_for_user(item_id, requester) do
          {:ok, item} -> [item]
          {:error, _reason} -> []
        end
      end)

    case items do
      [item] -> {:ok, item}
      [_first | _rest] -> {:error, :ambiguous_alert}
      [] -> correlate_generator_urls(urls, requester)
    end
  end

  defp correlate_generator_urls(urls, requester) do
    alerts = Grafana.find_alerts_by_generator_urls(urls)

    items =
      Enum.flat_map(alerts, fn alert ->
        case Forage.get_item_for_user("grafana_alert:#{alert.id}", requester) do
          {:ok, item} -> [item]
          {:error, _reason} -> []
        end
      end)

    case items do
      [item] -> {:ok, item}
      [] -> {:error, :alert_not_found}
      _items -> {:error, :ambiguous_alert}
    end
  end

  defp choose_repository(item, text) do
    repositories = CodingRuns.repositories_for_item(item)
    text = String.downcase(text)

    matches =
      Enum.filter(repositories, fn repository ->
        text =~ String.downcase(GitHubRepository.full_name(repository))
      end)

    case {repositories, matches} do
      {[], _matches} ->
        {:error, :repository_not_found}

      {[repository], []} ->
        {:ok, repository}

      {_repositories, [repository]} ->
        {:ok, repository}

      {repositories, []} ->
        {:error, {:choose_repository, Enum.map(repositories, &GitHubRepository.full_name/1)}}

      {_repositories, _matches} ->
        {:error, :repository_not_found}
    end
  end

  defp ensure_no_active_flight(item, repository) do
    case CodingRuns.active_for_item_repository(item.id, repository.id) do
      nil -> :ok
      flight -> {:error, {:active_flight, flight}}
    end
  end

  defp post_starting(installation, channel_id, thread_ts, objective) do
    API.post_message(installation, %{
      "channel" => channel_id,
      "thread_ts" => thread_ts,
      "text" => "Starting a *#{Flights.objective_label(objective)}* Flight..."
    })
  end

  defp post_reply(installation, channel_id, thread_ts, text) do
    case API.post_message(installation, %{
           "channel" => channel_id,
           "thread_ts" => thread_ts,
           "text" => text
         }) do
      {:ok, _response} -> {:handled, nil}
      {:error, reason} -> {:error, reason}
    end
  end
end
