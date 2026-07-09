defmodule Hive.Slack.Unfurl.BlockKit do
  @moduledoc """
  Builds Slack Block Kit payloads for Hive link unfurls.
  """

  @max_header_length 150
  @max_section_length 2_900
  @max_field_length 1_800
  @max_context_length 2_000
  @max_button_length 75

  def open_graph(%URI{} = uri, data) when is_map(data) do
    {:ok,
     payload(uri, %{
       description: Map.get(data, :description),
       highlights: Map.get(data, :highlights, []),
       section_label: Map.get(data, :section_label),
       title: Map.fetch!(data, :title),
       type_label: Map.get(data, :type_label)
     })}
  end

  def generic(%URI{} = uri, attrs) when is_map(attrs) do
    {:ok, payload(uri, attrs)}
  end

  defp payload(uri, attrs) do
    title = attrs |> Map.fetch!(:title) |> to_string()
    description = attrs |> Map.get(:description) |> present_string()
    section_label = attrs |> Map.get(:section_label) |> present_string()
    type_label = attrs |> Map.get(:type_label) |> present_string()
    highlights = attrs |> Map.get(:highlights, []) |> normalize_highlights()

    %{
      "blocks" =>
        [
          header_block(title),
          description_block(description),
          fields_block(highlights),
          context_block([type_label || section_label, "Hive"]),
          actions_block(uri)
        ]
        |> Enum.reject(&is_nil/1)
    }
  end

  defp header_block(title) do
    %{
      "type" => "header",
      "text" => %{
        "type" => "plain_text",
        "text" => title |> plain_text() |> truncate(@max_header_length),
        "emoji" => true
      }
    }
  end

  defp description_block(nil), do: nil

  defp description_block(description) do
    %{
      "type" => "section",
      "text" => %{
        "type" => "mrkdwn",
        "text" => description |> mrkdwn() |> truncate(@max_section_length)
      }
    }
  end

  defp fields_block([]), do: nil

  defp fields_block(highlights) do
    %{
      "type" => "section",
      "fields" =>
        highlights
        |> Enum.take(6)
        |> Enum.map(fn highlight ->
          %{
            "type" => "mrkdwn",
            "text" => highlight |> mrkdwn() |> prefix_bullet() |> truncate(@max_field_length)
          }
        end)
    }
  end

  defp context_block(parts) do
    text =
      parts
      |> Enum.map(&present_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join(" / ")

    if text == "" do
      nil
    else
      %{
        "type" => "context",
        "elements" => [
          %{
            "type" => "mrkdwn",
            "text" => text |> mrkdwn() |> truncate(@max_context_length)
          }
        ]
      }
    end
  end

  defp actions_block(uri) do
    %{
      "type" => "actions",
      "elements" => [
        %{
          "type" => "button",
          "text" => %{
            "type" => "plain_text",
            "text" => truncate("Open in Hive", @max_button_length),
            "emoji" => true
          },
          "url" => URI.to_string(uri),
          "action_id" => "open_hive_url"
        }
      ]
    }
  end

  defp normalize_highlights(highlights) when is_list(highlights) do
    highlights
    |> Enum.map(&present_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_highlights(_highlights), do: []

  defp present_string(nil), do: nil

  defp present_string(value) do
    value
    |> to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp plain_text(value), do: String.replace(value, ~r/\s+/, " ")

  defp mrkdwn(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp prefix_bullet(value), do: "- " <> value

  defp truncate(value, max_length) do
    if String.length(value) > max_length do
      suffix = "..."

      value
      |> String.slice(0, max(max_length - String.length(suffix), 0))
      |> Kernel.<>(suffix)
    else
      value
    end
  end
end
