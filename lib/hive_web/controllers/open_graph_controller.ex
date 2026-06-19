defmodule HiveWeb.OpenGraphController do
  @moduledoc false

  use HiveWeb, :controller

  alias Hive.Auth
  alias Hive.Drops
  alias Hive.Forage
  alias Hive.Specs
  alias HiveWeb.AccountLive
  alias HiveWeb.DropsLive
  alias HiveWeb.ForageLive
  alias HiveWeb.OpenGraph
  alias HiveWeb.PageHTML
  alias HiveWeb.SpecLive

  def show(conn, %{"page_id" => page_id, "hash" => hash}) do
    hash = normalize_hash(hash)

    with {:ok, data} <- page(conn, page_id),
         true <- OpenGraph.valid_hash?(data, hash) do
      OpenGraph.serve(conn, data)
    else
      _other ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(:not_found, "Not found")
    end
  end

  defp normalize_hash(hash), do: String.replace_suffix(hash, ".jpg", "")

  defp page(_conn, "login"), do: {:ok, PageHTML.open_graph()}
  defp page(_conn, "account-identities"), do: {:ok, AccountLive.Identities.open_graph()}

  defp page(conn, "forage") do
    user = current_user(conn)
    {items, meta} = Forage.list_forage_items_for_user(user, page_size: :all)

    {:ok, ForageLive.Index.open_graph(forage_stats(items, meta))}
  end

  defp page(_conn, "forage-feature-requests") do
    {:ok, ForageLive.FeatureRequests.open_graph(Forage.list_feature_requests())}
  end

  defp page(_conn, "forage-new"),
    do: {:ok, ForageLive.NewFeatureRequest.open_graph()}

  defp page(_conn, "forage-feature-requests-new"),
    do: {:ok, ForageLive.NewFeatureRequest.open_graph()}

  defp page(conn, "forage-item-manual-" <> id),
    do: forage_item_page(conn, "manual:" <> id)

  defp page(conn, "forage-item-github-issue-" <> id),
    do: forage_item_page(conn, "github_issue:" <> id)

  defp page(conn, "forage-item-grafana-alert-" <> id),
    do: forage_item_page(conn, "grafana_alert:" <> id)

  defp page(conn, "specs") do
    {:ok, SpecLive.Index.open_graph(Specs.list_specs(status: :draft, user: current_user(conn)))}
  end

  defp page(_conn, "specs-new"), do: {:ok, SpecLive.New.open_graph()}

  defp page(conn, "specs-edit-" <> number) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, current_user(conn)) do
      {:ok, SpecLive.Edit.open_graph(spec)}
    else
      :error
    end
  rescue
    Ecto.NoResultsError -> :error
  end

  defp page(conn, "spec-" <> number) do
    spec = Specs.get_spec_by_number!(number)

    if Specs.can_view?(spec, current_user(conn)) do
      {:ok, SpecLive.Show.open_graph(spec)}
    else
      :error
    end
  rescue
    Ecto.NoResultsError -> :error
  end

  defp page(_conn, "forage-" <> source_slug) do
    Forage.sources()
    |> Enum.find(&(ForageLive.Placeholder.open_graph_slug(&1) == source_slug))
    |> case do
      nil -> :error
      source -> {:ok, ForageLive.Placeholder.open_graph(source)}
    end
  end

  defp page(_conn, "drops"), do: {:ok, DropsLive.Index.open_graph()}
  defp page(_conn, "drops-subscribe"), do: {:ok, DropsLive.Subscribe.open_graph()}

  defp page(conn, "drop-" <> id) do
    case Drops.fetch_visible_drop(id, current_user(conn)) do
      {:ok, drop} -> {:ok, DropsLive.Show.open_graph(drop)}
      {:error, :not_found} -> :error
    end
  end

  defp page(_conn, _page_id), do: :error

  defp current_user(conn), do: Auth.current_user(conn)

  defp forage_item_page(conn, item_id) do
    case Forage.get_item_for_user(item_id, current_user(conn)) do
      {:ok, item} -> {:ok, ForageLive.Show.open_graph(item)}
      {:error, _reason} -> :error
    end
  end

  defp forage_stats(items, meta) do
    %{
      total: meta.total_count,
      open: Enum.count(items, &(&1.status in [:open, :firing])),
      domains:
        items
        |> Enum.flat_map(& &1.domains)
        |> Enum.map(& &1.id)
        |> Enum.uniq()
        |> length()
    }
  end
end
