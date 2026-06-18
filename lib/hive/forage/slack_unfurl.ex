defmodule Hive.Forage.SlackUnfurl do
  @moduledoc """
  Turns `/forage/items/:origin/:id` URLs into Slack unfurls.

  Items are fetched as the anonymous user so only items that anyone
  visiting the dashboard could see are surfaced; organization-only
  feature requests, Grafana alerts, and private-meadow GitHub issues
  are skipped.
  """

  @behaviour Hive.Slack.Unfurl

  alias Hive.Forage

  @origin_to_prefix %{
    "manual" => "manual:",
    "github-issue" => "github_issue:",
    "grafana-alert" => "grafana_alert:"
  }

  @impl true
  def unfurl(%URI{path: path} = uri) when is_binary(path) do
    case Path.split(path) do
      ["/", "forage", "items", origin, id] -> unfurl_item(origin, id, uri)
      _ -> :skip
    end
  end

  def unfurl(_uri), do: :skip

  defp unfurl_item(origin, id, uri) do
    with {:ok, prefix} <- Map.fetch(@origin_to_prefix, origin),
         {:ok, item} <- Forage.get_item_for_user(prefix <> id, nil) do
      {:ok, payload(item, uri)}
    else
      _ -> :skip
    end
  end

  defp payload(item, uri) do
    %{
      "title" => item.title,
      "title_link" => URI.to_string(uri),
      "text" => excerpt(item.body),
      "footer" => footer(item)
    }
  end

  defp footer(item) do
    parts =
      [
        "Hive",
        Forage.item_type_label(item.type),
        Forage.item_status_label(item.status)
      ]
      |> Enum.filter(&is_binary/1)

    Enum.join(parts, " · ")
  end

  defp excerpt(nil), do: nil

  defp excerpt(body) when is_binary(body) do
    body
    |> String.split(~r/\n+/, parts: 2)
    |> List.first()
    |> String.slice(0, 280)
  end
end
