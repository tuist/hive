defmodule Hive.Domains.SlackUnfurl do
  @moduledoc """
  Turns `/domains/:id` URLs into Slack unfurls. Private domains are
  skipped.
  """

  @behaviour Hive.Slack.Unfurl

  alias Hive.Domains
  alias Hive.Domains.Domain

  @impl true
  def unfurl(%URI{path: path} = uri) when is_binary(path) do
    case Path.split(path) do
      ["/", "domains", id] -> unfurl_domain(id, uri)
      _ -> :skip
    end
  end

  def unfurl(_uri), do: :skip

  defp unfurl_domain(id, uri) do
    case Domains.fetch_visible_domain(id, nil) do
      {:ok, %Domain{} = domain} -> {:ok, payload(domain, uri)}
      _ -> :skip
    end
  end

  defp payload(%Domain{} = domain, uri) do
    %{
      "title" => domain.name,
      "title_link" => URI.to_string(uri),
      "text" => domain.description,
      "footer" => "Hive · domain"
    }
  end
end
