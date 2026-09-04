defmodule Hive.Alerts.Destinations.Slack do
  @moduledoc """
  Sends an alert to a Slack channel on a Hive-installed workspace.

  The message is a Block Kit payload assembled to answer one question
  first: how bad is this? The header carries the issue's severity
  level and the tier's emoji; the fields row shows the numeric signals
  that separate "one-off transient" from "on fire right now" —
  environment, event count, level, and freshness (first / last seen).
  The mention prefix (`@here` / `@channel`) is what a rule's
  `:incident` tier typically uses to page a channel.
  """

  alias Hive.Alerts.Rule
  alias Hive.Errors.Issue
  alias Hive.Slack.API
  alias Hive.Slack.Installation
  alias HiveWeb.Endpoint

  @doc """
  Delivers the alert. Returns `:ok` on a Slack `chat.postMessage` 2xx,
  `{:error, reason}` otherwise. Called by the delivery worker after the
  cooldown check has passed.

  Options:
    * `:environment` — the triggering event's environment (e.g.
      `"production"`), surfaced in the severity fields.
  """
  def deliver(rule, issue, installation, reason, opts \\ [])

  def deliver(%Rule{} = rule, %Issue{} = issue, %Installation{} = installation, reason, opts) do
    if Installation.connected?(installation) do
      params = build_params(rule, issue, reason, opts)

      case API.post_message(installation, params) do
        {:ok, _body} -> :ok
        {:error, err} -> {:error, err}
      end
    else
      {:error, :installation_disconnected}
    end
  end

  def deliver(_rule, _issue, nil, _reason, _opts), do: {:error, :installation_missing}

  defp build_params(%Rule{} = rule, %Issue{} = issue, reason, opts) do
    environment = Keyword.get(opts, :environment)
    fallback = fallback_text(rule, issue, reason, environment)

    %{
      "channel" => rule.slack_channel_id,
      "text" => fallback,
      "blocks" => blocks(rule, issue, reason, environment),
      "unfurl_links" => false,
      "unfurl_media" => false
    }
  end

  defp fallback_text(%Rule{tier: tier}, %Issue{} = issue, reason, environment) do
    env_part = if environment in [nil, ""], do: "", else: " · #{environment}"

    "#{tier_emoji(tier)} #{tier_label(tier)} · #{reason_label(reason)} · " <>
      "#{level_label(issue.level)}#{env_part} · #{issue.title}"
  end

  defp blocks(%Rule{} = rule, %Issue{} = issue, reason, environment) do
    prefix = mention_prefix(rule.slack_mention)
    header = "#{tier_emoji(rule.tier)} #{tier_label(rule.tier)}: #{reason_label(reason)}"

    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => truncate(header, 150), "emoji" => true}
      }
    ]
    |> maybe_prepend_mention(prefix)
    |> Kernel.++([
      title_block(issue),
      severity_fields_block(issue, environment),
      %{"type" => "divider"},
      context_block(rule, issue),
      actions_block(issue)
    ])
  end

  # `@here` / `@channel` must live in a real `section` (or plain text
  # message) — the `header` block strips mention syntax. Emit a small
  # context section above the header when a mention is requested.
  defp maybe_prepend_mention(blocks, ""), do: blocks

  defp maybe_prepend_mention(blocks, prefix) do
    [
      %{
        "type" => "section",
        "text" => %{"type" => "mrkdwn", "text" => String.trim(prefix)}
      }
      | blocks
    ]
  end

  defp title_block(%Issue{} = issue) do
    url = issue_url(issue)

    subtitle =
      case culprit_line(issue) do
        nil -> ""
        line -> "\n`#{escape(line)}`"
      end

    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => "*<#{url}|#{escape(truncate(issue.title, 200))}>*#{subtitle}"
      }
    }
  end

  # The "how bad is this?" row. Slack lays fields out in two columns,
  # so we pair the highest-signal metrics first: level next to
  # environment, then event volume next to when it was last seen.
  defp severity_fields_block(%Issue{} = issue, environment) do
    %{
      "type" => "section",
      "fields" => [
        field("Level", level_field(issue.level)),
        field("Environment", environment_field(environment)),
        field("Events", format_count(issue.event_count)),
        field("Last seen", relative_time(issue.last_seen)),
        field("First seen", relative_time(issue.first_seen)),
        field("Status", status_field(issue.status))
      ]
    }
  end

  defp field(label, value) do
    %{"type" => "mrkdwn", "text" => "*#{label}*\n#{value}"}
  end

  defp context_block(%Rule{} = rule, %Issue{} = issue) do
    %{
      "type" => "context",
      "elements" => [
        %{
          "type" => "mrkdwn",
          "text" => "Project: *#{escape(project_name(issue))}*"
        },
        %{"type" => "mrkdwn", "text" => "Rule: #{escape(rule.name)}"},
        %{"type" => "mrkdwn", "text" => "Fingerprint: `#{short_fingerprint(issue.fingerprint)}`"}
      ]
    }
  end

  defp actions_block(%Issue{} = issue) do
    %{
      "type" => "actions",
      "elements" => [
        %{
          "type" => "button",
          "text" => %{"type" => "plain_text", "text" => "Open issue", "emoji" => true},
          "url" => issue_url(issue),
          "style" => "primary"
        }
      ]
    }
  end

  ## Formatting helpers

  defp mention_prefix(:here), do: "<!here> "
  defp mention_prefix(:channel), do: "<!channel> "
  defp mention_prefix(_none), do: ""

  # A single glance emoji so people can scan a busy channel and pick
  # the fatal / incident ones out first.
  defp tier_emoji(:incident), do: "🚨"
  defp tier_emoji(_attention), do: "⚠️"

  defp tier_label(:incident), do: "Incident"
  defp tier_label(_attention), do: "Attention"

  defp reason_label(:new_issue_threshold), do: "New issue crossed threshold"
  defp reason_label(:regression), do: "Regression"
  defp reason_label(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_label(reason) when is_binary(reason), do: reason
  defp reason_label(_), do: "alert"

  # Prefix fatal / error with a colored dot so severity reads at a
  # glance in the fields column without depending on the header emoji.
  defp level_field(:fatal), do: "🟣 fatal"
  defp level_field(:error), do: "🔴 error"
  defp level_field(:warning), do: "🟡 warning"
  defp level_field(:info), do: "🔵 info"
  defp level_field(:debug), do: "⚪ debug"
  defp level_field(nil), do: "—"
  defp level_field(other), do: to_string(other)

  defp level_label(nil), do: "unknown"
  defp level_label(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp level_label(other), do: to_string(other)

  defp status_field(:resolved), do: "resolved"
  defp status_field(:ignored), do: "ignored"
  defp status_field(:unresolved), do: "unresolved"
  defp status_field(nil), do: "—"
  defp status_field(other), do: to_string(other)

  # Production reads bolder than staging so an on-call scanning a
  # busy channel can tell them apart at a glance.
  defp environment_field(nil), do: "—"
  defp environment_field(""), do: "—"

  defp environment_field(env) when is_binary(env) do
    if env in ~w(production prod live) do
      "*`#{escape(env)}`*"
    else
      "`#{escape(env)}`"
    end
  end

  defp environment_field(other), do: to_string(other)

  defp format_count(nil), do: "0"
  defp format_count(n) when is_integer(n) and n >= 1_000_000, do: "#{div(n, 1_000_000)}M"
  defp format_count(n) when is_integer(n) and n >= 1_000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_count(n) when is_integer(n), do: Integer.to_string(n)
  defp format_count(other), do: to_string(other)

  # "just now" / "2m ago" / "3h ago" / "5d ago" reads faster than an
  # ISO timestamp for the "is this on fire right now?" question.
  defp relative_time(nil), do: "—"

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp culprit_line(%Issue{culprit: culprit}) when is_binary(culprit) and culprit != "" do
    truncate(culprit, 200)
  end

  defp culprit_line(_), do: nil

  defp project_name(%Issue{project: %Hive.Projects.Project{name: name}}) when is_binary(name),
    do: name

  defp project_name(_), do: "unknown"

  defp issue_url(%Issue{id: id}), do: Endpoint.url() <> "/errors/#{id}"

  defp short_fingerprint(fp) when is_binary(fp) and byte_size(fp) >= 8, do: String.slice(fp, 0, 8)
  defp short_fingerprint(_), do: "—"

  defp truncate(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  defp truncate(text, _max), do: to_string(text)

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
