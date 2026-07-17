defmodule HiveWeb.Api.V1.Presenter do
  @moduledoc false

  alias Hive.Forage.Item
  alias Hive.Drops.Drop
  alias Hive.Drops.WeeklyDigest
  alias Hive.Specs
  alias Hive.Specs.Spec

  def user(user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      role: to_string(user.role)
    }
  end

  def forage_item(%Item{} = item) do
    %{
      id: item.id,
      type: to_string(item.type),
      title: item.title,
      body: item.body,
      status: to_string(item.status),
      visibility: string_or_nil(item.visibility),
      source_label: item.source_label,
      external_label: item.external_label,
      external_url: item.external_url,
      occurred_at: item.occurred_at,
      updated_at: item.updated_at,
      domains: Enum.map(item.domains, &domain/1)
    }
  end

  def spec(%Spec{} = spec) do
    %{
      id: spec.id,
      number: spec.number,
      title: spec.title,
      summary: spec.summary,
      body: spec.body,
      status: to_string(spec.status),
      visibility: spec |> Specs.effective_visibility() |> to_string(),
      revision: spec.lock_version,
      has_new_activity: spec.has_new_activity,
      updated_at: spec.updated_at,
      domains: Enum.map(spec.domains, &domain/1)
    }
  end

  def drop(%Drop{} = drop) do
    %{
      id: drop.id,
      number: drop.number,
      title: drop.title,
      body: drop_body(drop),
      source_type: to_string(drop.source_type),
      version: drop.version,
      url: drop.url,
      published_at: drop.published_at,
      domains: Enum.map(drop.domains, &domain/1)
    }
  end

  def drop_digest(%WeeklyDigest{} = digest) do
    %{
      id: digest.id,
      week_start: digest.week_start,
      week_end: digest.week_end,
      title: digest.title,
      summary: digest.summary,
      body: digest.body,
      drop_count: length(digest.drop_ids),
      published_at: digest.published_at
    }
  end

  def pagination(%{current_page: current_page, total_entries: total_entries} = meta) do
    %{
      page: current_page,
      page_size: meta.page_size,
      total_count: total_entries,
      total_pages: meta.total_pages
    }
  end

  def pagination(%{current_page: current_page, total_count: total_count} = meta) do
    %{
      page: current_page,
      page_size: meta.page_size,
      total_count: total_count,
      total_pages: meta.total_pages
    }
  end

  def pagination(meta) do
    %{
      page: meta.page,
      page_size: meta.page_size,
      total_count: meta.total_count,
      total_pages: meta.total_pages
    }
  end

  defp domain(domain), do: %{id: domain.id, name: domain.name}

  defp drop_body(%Drop{source_type: :rss, body: body}),
    do: HiveWeb.Markdown.to_plain_text(body)

  defp drop_body(%Drop{body: body}), do: body

  defp string_or_nil(nil), do: nil
  defp string_or_nil(value), do: to_string(value)
end
