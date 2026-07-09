defmodule Hive.Slack.Unfurler do
  @moduledoc """
  Dispatches a URL shared in Slack to the dashboard route that owns it.

  Only URLs whose host matches `HiveWeb.Endpoint`'s configured host
  are considered: a workspace pasting an unrelated link must never
  receive a Hive-branded unfurl for it.
  """

  alias Hive.Slack.Unfurl.BlockKit

  @doc """
  Returns `{:ok, payload}` if the owning route can unfurl the URL, or
  `:skip` when the URL isn't a Hive URL or the route should not expose it.
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
    case route_info(uri) do
      %{plug: Phoenix.LiveView.Plug, log_module: module, path_params: params} ->
        unfurl_with_route(module, uri, params)

      %{plug: module, path_params: params} when is_atom(module) ->
        unfurl_with_route(module, uri, params)

      _other ->
        :skip
    end
  rescue
    Ecto.NoResultsError -> :skip
    Ecto.Query.CastError -> :skip
  end

  defp route_info(uri) do
    Phoenix.Router.route_info(HiveWeb.Router, "GET", uri.path || "/", uri.host)
  end

  defp unfurl_with_route(module, uri, params) do
    case Code.ensure_loaded(module) do
      {:module, _module} ->
        cond do
          function_exported?(module, :slack_unfurl, 2) ->
            module.slack_unfurl(uri, params)

          function_exported?(module, :open_graph, 0) ->
            BlockKit.open_graph(uri, module.open_graph())

          true ->
            :skip
        end

      _error ->
        :skip
    end
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
