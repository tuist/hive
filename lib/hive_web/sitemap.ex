defmodule HiveWeb.Sitemap do
  @moduledoc false

  alias Hive.Domains
  alias Hive.Drops
  alias Hive.Drops.WeeklyDigests
  alias Hive.Forage
  alias Hive.Postmortems
  alias Hive.Projects
  alias Hive.Specs
  alias HiveWeb.Endpoint
  alias HiveWeb.FeedXML
  alias HiveWeb.ForageLive.Show, as: ForageShow

  def render do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      Enum.map(urls(), &render_url/1),
      "</urlset>\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp urls do
    (static_urls() ++
       forage_urls() ++
       spec_urls() ++
       postmortem_urls() ++
       drop_urls() ++
       digest_urls() ++
       domain_urls() ++
       project_urls())
    |> Enum.uniq_by(& &1.location)
    |> Enum.sort_by(& &1.location)
  end

  defp static_urls do
    [%{location: absolute_url("/"), updated_at: nil}] ++
      Enum.map(Forage.visible_sources(nil), &url(&1.path, nil)) ++
      Enum.map(
        ["/forage", "/specs", "/postmortems", "/drops", "/drops/digest", "/domains", "/projects"],
        &url(&1, nil)
      )
  end

  defp forage_urls do
    {items, _meta} = Forage.list_forage_items_for_user(nil, page_size: :all)
    Enum.map(items, &url(ForageShow.item_path(&1), &1.updated_at))
  end

  defp spec_urls do
    Specs.list_specs(user: nil)
    |> Enum.map(&url("/specs/#{&1.number}", &1.updated_at))
  end

  defp postmortem_urls do
    Postmortems.list_postmortems(nil)
    |> Enum.map(&url("/postmortems/#{&1.number}", &1.updated_at))
  end

  defp drop_urls do
    {drops, _meta} = Drops.list_drops(user: nil, page_size: :all)
    Enum.map(drops, &url(Drops.public_path(&1), &1.updated_at))
  end

  defp digest_urls do
    WeeklyDigests.list_published(limit: 10_000)
    |> Enum.map(&url(WeeklyDigests.public_path(&1), &1.updated_at))
  end

  defp domain_urls do
    Domains.list_visible_domains(nil)
    |> Enum.map(&url("/domains/#{&1.id}", &1.updated_at))
  end

  defp project_urls do
    Projects.list_visible_projects(nil)
    |> Enum.map(&url("/projects/#{&1.id}", &1.updated_at))
  end

  defp url(path, updated_at), do: %{location: absolute_url(path), updated_at: updated_at}
  defp absolute_url(path), do: Endpoint.url() <> path

  defp render_url(%{location: location, updated_at: updated_at}) do
    [
      "<url>\n",
      FeedXML.tag("loc", location),
      lastmod(updated_at),
      "</url>\n"
    ]
  end

  defp lastmod(%DateTime{} = updated_at),
    do: FeedXML.tag("lastmod", Date.to_iso8601(DateTime.to_date(updated_at)))

  defp lastmod(%NaiveDateTime{} = updated_at),
    do: FeedXML.tag("lastmod", Date.to_iso8601(NaiveDateTime.to_date(updated_at)))

  defp lastmod(_updated_at), do: []
end
