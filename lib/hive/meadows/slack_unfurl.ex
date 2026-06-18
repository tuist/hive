defmodule Hive.Meadows.SlackUnfurl do
  @moduledoc """
  Turns `/meadows/:id` URLs into Slack unfurls. Private meadows are
  skipped.
  """

  @behaviour Hive.Slack.Unfurl

  alias Hive.Meadows
  alias Hive.Meadows.Meadow

  @impl true
  def unfurl(%URI{path: path} = uri) when is_binary(path) do
    case Path.split(path) do
      ["/", "meadows", id] -> unfurl_meadow(id, uri)
      _ -> :skip
    end
  end

  def unfurl(_uri), do: :skip

  defp unfurl_meadow(id, uri) do
    case Meadows.fetch_visible_meadow(id, nil) do
      {:ok, %Meadow{} = meadow} -> {:ok, payload(meadow, uri)}
      _ -> :skip
    end
  end

  defp payload(%Meadow{} = meadow, uri) do
    %{
      "title" => meadow.name,
      "title_link" => URI.to_string(uri),
      "text" => meadow.description,
      "footer" => "Hive · meadow"
    }
  end
end
