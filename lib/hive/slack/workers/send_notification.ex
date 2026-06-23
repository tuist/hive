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
  alias Hive.Specs
  alias Hive.Specs.Comment
  alias Hive.Specs.ReviewRequests
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
  def perform(%Oban.Job{args: %{"event" => "spec.review.requested"} = args}) do
    post_review_request(args)
  end

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
    |> Enum.reduce_while(:ok, &post_to_target(&1, message, &2))
  end

  defp post_review_request(%{"spec_id" => spec_id, "requester_id" => requester_id}) do
    with %Spec{} = spec <- load_spec(spec_id),
         %Hive.Accounts.User{} = requester <- Hive.Accounts.get_user(requester_id),
         {:ok, payload} <- ReviewRequests.draft(spec, requester) do
      "spec.review.requested"
      |> Slack.notification_targets_for()
      |> Enum.reduce_while(:ok, &post_review_request_to_target(&1, spec, requester, payload, &2))
    else
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp post_review_request(_args), do: :ok

  defp post_review_request_to_target(
         %Installation{} = installation,
         spec,
         requester,
         payload,
         :ok
       ) do
    if Installation.connected?(installation) do
      message =
        installation
        |> review_request_message(spec, requester, payload)
        |> Map.put("channel", installation.notification_channel_id)

      case API.post_message(installation, message) do
        {:ok, _} ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.warning(
            "[Slack.SendNotification] review request post failed: #{inspect(reason)}"
          )

          {:halt, {:error, reason}}
      end
    else
      {:cont, :ok}
    end
  end

  defp post_to_target(%Installation{} = installation, message, :ok) do
    if Installation.connected?(installation) do
      do_post_to_target(installation, message)
    else
      {:cont, :ok}
    end
  end

  defp do_post_to_target(%Installation{} = installation, message) do
    message = Map.put(message, "channel", installation.notification_channel_id)

    case API.post_message(installation, message) do
      {:ok, _} ->
        {:cont, :ok}

      {:error, reason} ->
        Logger.warning("[Slack.SendNotification] post failed: #{inspect(reason)}")
        {:halt, {:error, reason}}
    end
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

  defp review_request_message(%Installation{} = installation, %Spec{} = spec, requester, payload) do
    url = spec_url(spec)
    reviewer_text = reviewers_text(installation, Map.get(payload, :reviewers, []))
    summary = Map.get(payload, :summary, summary_text(spec))
    review_focus = Map.get(payload, :review_focus, [])
    revision = Map.get(payload, :last_revision)

    blocks =
      [
        section("*Review requested:* <#{url}|##{spec.number} #{escape(spec.title)}>"),
        context([
          "Requested by #{user_or_slack_label(installation, requester)}",
          "Status: #{status_label(spec.status)}",
          revision_context(revision, spec)
        ]),
        section(escape(summary)),
        maybe_reviewers_section(reviewer_text),
        maybe_review_focus_section(review_focus),
        actions([
          %{
            "type" => "button",
            "text" => %{"type" => "plain_text", "text" => "Open spec"},
            "url" => url
          }
        ])
      ]
      |> Enum.reject(&is_nil/1)

    %{
      "text" => "Review requested for spec ##{spec.number}: #{spec.title}",
      "blocks" => blocks
    }
  end

  defp maybe_reviewers_section(""), do: nil
  defp maybe_reviewers_section(text), do: section("*Reviewers:* #{text}")

  defp maybe_review_focus_section([]), do: nil

  defp maybe_review_focus_section(review_focus) do
    text =
      review_focus
      |> Enum.map(&"- #{escape(&1)}")
      |> Enum.join("\n")

    section("*Review focus:*\n#{text}")
  end

  defp reviewers_text(%Installation{} = installation, reviewers) do
    slack_profiles =
      installation
      |> Slack.linked_user_profiles_by_user_ids(Enum.map(reviewers, & &1.id))

    reviewers
    |> Enum.map(fn reviewer ->
      case Map.get(slack_profiles, reviewer.id) do
        %{slack_user_id: slack_user_id} when is_binary(slack_user_id) ->
          "<@#{slack_user_id}>"

        _profile ->
          escape(user_label(reviewer))
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp user_or_slack_label(%Installation{} = installation, user) do
    user_id = user.id

    case Slack.linked_user_profiles_by_user_ids(installation, [user.id]) do
      %{^user_id => %{slack_user_id: slack_user_id}} when is_binary(slack_user_id) ->
        "<@#{slack_user_id}>"

      _profiles ->
        escape(user_label(user))
    end
  end

  defp revision_context(nil, %Spec{lock_version: lock_version}), do: "Revision #{lock_version}"

  defp revision_context(%{revision: revision, inserted_at: inserted_at}, _spec) do
    ["Revision #{revision}", date_label(inserted_at)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" - ")
  end

  defp revision_context(%{revision: revision}, _spec), do: "Revision #{revision}"

  defp actions(elements), do: %{"type" => "actions", "elements" => elements}

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

  defp date_label(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d, %Y")
  defp date_label(_datetime), do: nil

  defp summary_text(%Spec{summary: summary}) when is_binary(summary) and summary != "",
    do: summary

  defp summary_text(%Spec{body: body}), do: body

  defp spec_url(%Spec{number: number}), do: HiveWeb.Endpoint.url() <> "/specs/#{number}"

  defp load_spec(spec_id) do
    spec_id
    |> Specs.get_spec!()
  rescue
    Ecto.NoResultsError -> nil
  end

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
