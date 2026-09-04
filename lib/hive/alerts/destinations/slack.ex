defmodule Hive.Alerts.Destinations.Slack do
  @moduledoc """
  Sends an alert to a Slack channel on a Hive-installed workspace.

  The destination is described by three fields on `Hive.Alerts.Rule`:
  `slack_installation_id`, `slack_channel_id`, and `slack_mention`. The
  mention prefix (`<!here>` / `<!channel>`) is what a rule's `:incident`
  tier typically uses to page a channel.
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
  """
  def deliver(%Rule{} = rule, %Issue{} = issue, %Installation{} = installation, reason) do
    if Installation.connected?(installation) do
      params = build_params(rule, issue, installation, reason)

      case API.post_message(installation, params) do
        {:ok, _body} -> :ok
        {:error, err} -> {:error, err}
      end
    else
      {:error, :installation_disconnected}
    end
  end

  def deliver(_rule, _issue, nil, _reason), do: {:error, :installation_missing}

  defp build_params(%Rule{} = rule, %Issue{} = issue, %Installation{} = installation, reason) do
    prefix = mention_prefix(rule.slack_mention)
    headline = headline(rule, issue, reason)
    fallback = "#{prefix}#{headline}"

    %{
      "channel" => rule.slack_channel_id,
      "text" => fallback,
      "blocks" => blocks(rule, issue, prefix, headline, reason),
      "unfurl_links" => false,
      "unfurl_media" => false
    }
    |> Map.merge(workspace_hint(installation))
  end

  defp workspace_hint(_installation), do: %{}

  defp headline(%Rule{tier: tier}, %Issue{} = issue, reason) do
    tier_label = tier_label(tier)
    reason_label = reason_label(reason)
    "[#{tier_label}] #{reason_label}: #{issue.title}"
  end

  defp mention_prefix(:here), do: "<!here> "
  defp mention_prefix(:channel), do: "<!channel> "
  defp mention_prefix(_none), do: ""

  defp blocks(%Rule{} = rule, %Issue{} = issue, prefix, headline, reason) do
    project_name = project_name(issue)
    issue_url = issue_url(issue)

    [
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => "#{prefix}*#{escape(headline)}*"
        }
      },
      %{
        "type" => "context",
        "elements" => [
          %{"type" => "mrkdwn", "text" => "Project: *#{escape(project_name)}*"},
          %{"type" => "mrkdwn", "text" => "Rule: #{escape(rule.name)}"},
          %{"type" => "mrkdwn", "text" => "Events: #{issue.event_count}"},
          %{"type" => "mrkdwn", "text" => "Trigger: #{reason_label(reason)}"}
        ]
      },
      %{
        "type" => "actions",
        "elements" => [
          %{
            "type" => "button",
            "text" => %{"type" => "plain_text", "text" => "Open issue"},
            "url" => issue_url,
            "style" => "primary"
          }
        ]
      }
    ]
  end

  defp project_name(%Issue{project: %Hive.Projects.Project{name: name}}) when is_binary(name),
    do: name

  defp project_name(_issue), do: "unknown"

  defp issue_url(%Issue{id: id}), do: Endpoint.url() <> "/errors/#{id}"

  defp tier_label(:incident), do: "Incident"
  defp tier_label(_attention), do: "Attention"

  defp reason_label(:new_issue_threshold), do: "New issue crossed threshold"
  defp reason_label(:regression), do: "Regression"
  defp reason_label(other) when is_atom(other), do: Atom.to_string(other)
  defp reason_label(other) when is_binary(other), do: other
  defp reason_label(_other), do: "alert"

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
