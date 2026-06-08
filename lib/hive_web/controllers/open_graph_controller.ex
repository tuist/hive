defmodule HiveWeb.OpenGraphController do
  @moduledoc false

  use HiveWeb, :controller

  alias Hive.Forage
  alias Hive.Specs
  alias HiveWeb.AccountLive
  alias HiveWeb.ForageLive
  alias HiveWeb.OpenGraph
  alias HiveWeb.PageHTML
  alias HiveWeb.SpecLive

  def show(conn, %{"page_id" => page_id, "hash" => hash}) do
    with {:ok, data} <- page(page_id),
         true <- OpenGraph.valid_hash?(data, hash) do
      OpenGraph.serve(conn, data)
    else
      _other ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(:not_found, "Not found")
    end
  end

  defp page("login"), do: {:ok, PageHTML.open_graph()}
  defp page("account-identities"), do: {:ok, AccountLive.Identities.open_graph()}

  defp page("forage-feature-requests") do
    {:ok, ForageLive.FeatureRequests.open_graph(Forage.list_feature_requests())}
  end

  defp page("forage-feature-requests-new"), do: {:ok, ForageLive.NewFeatureRequest.open_graph()}

  defp page("specs"), do: {:ok, SpecLive.Index.open_graph(Specs.list_specs(status: :draft))}

  defp page("specs-new"), do: {:ok, SpecLive.New.open_graph()}

  defp page("specs-edit-" <> number) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, nil) do
      {:ok, SpecLive.Edit.open_graph(spec)}
    else
      :error
    end
  rescue
    Ecto.NoResultsError -> :error
  end

  defp page("spec-" <> number) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, nil) do
      {:ok, SpecLive.Show.open_graph(spec)}
    else
      :error
    end
  rescue
    Ecto.NoResultsError -> :error
  end

  defp page("forage-" <> source_slug) do
    Forage.sources()
    |> Enum.find(&(ForageLive.Placeholder.open_graph_slug(&1) == source_slug))
    |> case do
      nil -> :error
      source -> {:ok, ForageLive.Placeholder.open_graph(source)}
    end
  end

  defp page(_page_id), do: :error
end
