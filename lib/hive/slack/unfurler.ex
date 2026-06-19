defmodule Hive.Slack.Unfurler do
  @moduledoc """
  Dispatches a URL shared in Slack to the first registered
  `Hive.Slack.Unfurl` implementation that recognizes it.

  Only URLs whose host matches `HiveWeb.Endpoint`'s configured host
  are considered: a workspace pasting an unrelated link must never
  receive a Hive-branded unfurl for it.
  """

  @unfurlers [
    Hive.Specs.SlackUnfurl,
    Hive.Domains.SlackUnfurl,
    Hive.Forage.SlackUnfurl
  ]

  @doc """
  Returns the registered unfurl modules. Mostly useful for tests and
  introspection; production code should call `unfurl/1`.
  """
  def unfurlers, do: @unfurlers

  @doc """
  Returns `{:ok, payload}` if any registered module can unfurl the URL,
  or `:skip` when the URL isn't a Hive URL or no module wants it.
  """
  def unfurl(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} = uri when is_binary(host) ->
        if app_url?(uri), do: dispatch(uri), else: :skip

      _ ->
        :skip
    end
  end

  defp dispatch(uri) do
    Enum.find_value(@unfurlers, :skip, fn module ->
      case module.unfurl(uri) do
        {:ok, payload} -> {:ok, payload}
        :skip -> nil
      end
    end)
  end

  defp app_url?(%URI{host: host}) do
    case URI.parse(HiveWeb.Endpoint.url()) do
      %URI{host: app_host} when is_binary(app_host) ->
        String.downcase(host) == String.downcase(app_host)

      _ ->
        false
    end
  end
end
