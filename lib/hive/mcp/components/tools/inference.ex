defmodule Hive.MCP.Components.Tools.Inference do
  @moduledoc false

  alias Hive.Inference.ModelBinding
  alias Hive.Inference.Token

  def profile_json(%ModelBinding{} = profile) do
    %{
      id: profile.id,
      name: profile.name,
      description: profile.description,
      upstream_provider: profile.upstream_provider,
      upstream_model: profile.upstream_model,
      input_cost_per_million: decimal(profile.input_cost_per_million),
      output_cost_per_million: decimal(profile.output_cost_per_million),
      enabled: profile.enabled,
      hive_inference: profile.hive_inference,
      hive_coding: profile.hive_coding,
      hive_embedding: profile.hive_embedding,
      last_used_at: iso8601(profile.last_used_at),
      token_count: length(profile.tokens || []),
      inserted_at: iso8601(profile.inserted_at),
      updated_at: iso8601(profile.updated_at)
    }
  end

  def provider_json(provider) do
    %{
      id: provider.id,
      base_url: provider.base_url,
      configured: provider.configured?,
      credential_configured: provider.credential_configured?,
      endpoint_configured: provider.endpoint_configured?,
      profile_count: provider.profile_count,
      source: Atom.to_string(provider.source),
      timeout: provider.timeout
    }
  end

  def token_json(%Token{model_binding: %ModelBinding{} = profile} = token) do
    %{
      id: token.id,
      name: token.name,
      profile: %{id: profile.id, name: profile.name},
      hive_role: token.hive_role,
      enabled: token.enabled,
      expires_at: iso8601(token.expires_at),
      last_used_at: iso8601(token.last_used_at),
      inserted_at: iso8601(token.inserted_at),
      updated_at: iso8601(token.updated_at)
    }
  end

  def usage_json(summary) do
    %{
      request_count: summary.request_count,
      input_tokens: summary.input_tokens,
      output_tokens: summary.output_tokens,
      total_tokens: summary.total_tokens,
      cost_usd: decimal(summary.cost_usd)
    }
  end

  def pagination_json(meta) do
    %{
      current_page: meta.current_page,
      page_size: meta.page_size,
      total_count: meta.total_entries,
      total_pages: meta.total_pages,
      has_next_page?: meta.current_page < meta.total_pages,
      has_previous_page?: meta.current_page > 1
    }
  end

  def iso8601(nil), do: nil
  def iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  def decimal(nil), do: nil

  def decimal(%Decimal{} = value) do
    case Decimal.to_string(value, :normal) |> String.split(".", parts: 2) do
      [whole] ->
        whole

      [whole, fractional] ->
        case String.trim_trailing(fractional, "0") do
          "" -> whole
          fractional -> whole <> "." <> fractional
        end
    end
  end

  def decimal(value), do: to_string(value)
end
