defmodule Hive.Slack.Workers.SendNotification do
  @moduledoc """
  Posts configured product activity notifications into Slack.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: 60, states: :incomplete]

  require Logger

  alias Hive.Repo
  alias Hive.Slack
  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias Hive.Specs.Comment
  alias Hive.Specs.Spec

  def enqueue(event, args) when is_binary(event) and is_map(args) do
    if Slack.notification_enabled_for?(event) do
      args
      |> Map.put("event", event)
      |> new()
      |> Oban.insert()
    else
      :skipped
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event" => event} = args}) do
    case message_for(event, args) do
      {:ok, message} ->
        post_to_targets(event, message)

      {:skipped, _reason} ->
        :ok

      {:error, :not_found} ->
        :ok
    end
  end

  defp post_to_targets(event, message) do
    event
    |> Slack.notification_targets_for()
    |> Enum.reduce_while(:ok, fn installation, :ok ->
      if Installation.connected?(installation) do
        message = Map.put(message, "channel", installation.notification_channel_id)

        case API.post_message(installation, message) do
          {:ok, _} ->
            {:cont, :ok}

          {:error, reason} ->
            Logger.warning("[Slack.SendNotification] post failed: #{inspect(reason)}")
            {:halt, {:error, reason}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  defp message_for("spec.created", %{"spec_id" => spec_id}) do
    case Repo.get(Spec, spec_id) do
      nil ->
        {:error, :not_found}

      spec ->
        url = spec_url(spec)

        {:ok,
         %{
           "text" => "New spec: #{spec.title}",
           "blocks" => [
             section("*New spec:* <#{url}|##{spec.number} #{escape(spec.title)}>"),
             context([
               author_text("Created by", spec.created_by_user_id),
               "Status: #{status_label(spec.status)}"
             ]),
             section(summary_text(spec))
           ]
         }}
    end
  end

  defp message_for("spec.comment.created", %{"comment_id" => comment_id}) do
    case Repo.get(Comment, comment_id) do
      nil ->
        {:error, :not_found}

      comment ->
        %Comment{spec: spec} = comment = Repo.preload(comment, [:user, :spec])
        url = spec_url(spec)

        {:ok,
         %{
           "text" => "New spec comment: #{spec.title}",
           "blocks" => [
             section("*New comment on spec:* <#{url}|##{spec.number} #{escape(spec.title)}>"),
             context([comment_author_text(comment)]),
             section(comment.body)
           ]
         }}
    end
  end

  defp message_for(_event, _args), do: {:skipped, :unknown_event}

  defp section(text), do: %{"type" => "section", "text" => mrkdwn(text)}

  defp context(elements) do
    %{
      "type" => "context",
      "elements" => Enum.map(elements, &mrkdwn/1)
    }
  end

  defp mrkdwn(text), do: %{"type" => "mrkdwn", "text" => truncate(text, 3_000)}

  defp author_text(prefix, user_id) do
    user_id
    |> Hive.Accounts.get_user()
    |> case do
      nil -> prefix
      user -> "#{prefix} #{user_label(user)}"
    end
  end

  defp comment_author_text(%Comment{user: nil, author_name: name}) when is_binary(name),
    do: "Comment by #{name}"

  defp comment_author_text(%Comment{user: user}), do: "Comment by #{user_label(user)}"

  defp user_label(%{name: name}) when is_binary(name), do: name
  defp user_label(%{email: email}) when is_binary(email), do: email
  defp user_label(_user), do: "someone"

  defp status_label(status) when is_atom(status),
    do: status |> Atom.to_string() |> String.replace("_", " ")

  defp status_label(status), do: to_string(status)

  defp summary_text(%Spec{summary: summary}) when is_binary(summary) and summary != "",
    do: summary

  defp summary_text(%Spec{body: body}), do: body

  defp spec_url(%Spec{number: number}), do: HiveWeb.Endpoint.url() <> "/specs/#{number}"

  defp truncate(text, max) when is_binary(text) and byte_size(text) > max do
    String.slice(text, 0, max - 3) <> "..."
  end

  defp truncate(text, _max) when is_binary(text), do: text
  defp truncate(text, _max), do: to_string(text)

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
