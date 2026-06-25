defmodule Hive.Inference do
  @moduledoc """
  OpenAI-compatible inference relay model bindings and tokens.
  """

  import Ecto.Query

  alias Hive.Inference.ModelBinding
  alias Hive.Inference.ModelIdentifier
  alias Hive.Inference.Provider
  alias Hive.Inference.Token
  alias Hive.Inference.Usage
  alias Hive.Repo

  @config_key {__MODULE__, :config}
  @token_bytes 32
  @token_prefix "hinf_"
  @token_attr_key_map %{
    "name" => :name,
    "enabled" => :enabled,
    "expires_at" => :expires_at
  }
  @token_attr_keys Map.values(@token_attr_key_map)

  def list_model_bindings do
    ModelBinding
    |> order_by([binding], asc: binding.name)
    |> Repo.all()
  end

  def list_profiles do
    ModelBinding
    |> order_by([binding], asc: binding.name)
    |> preload(tokens: ^tokens_query())
    |> Repo.all()
  end

  def get_model_binding!(id), do: Repo.get!(ModelBinding, id)

  def get_profile!(id) do
    ModelBinding
    |> preload(tokens: ^tokens_query())
    |> Repo.get!(id)
  end

  def get_token!(id), do: Repo.get!(Token, id)

  def get_token_with_profile!(id) do
    Token
    |> preload(:model_binding)
    |> Repo.get!(id)
  end

  def get_model_binding_by_name(name) when is_binary(name) do
    Repo.get_by(ModelBinding, name: name)
  end

  def change_model_binding(%ModelBinding{} = binding, attrs \\ %{}) do
    ModelBinding.changeset(binding, attrs)
  end

  def change_profile(%ModelBinding{} = profile, attrs \\ %{}) do
    change_model_binding(profile, attrs)
  end

  def change_token(%ModelBinding{id: profile_id}, attrs \\ %{}) do
    %Token{model_binding_id: profile_id, token_hash: "pending"}
    |> Token.changeset(normalize_token_attrs(attrs))
  end

  def create_model_binding(attrs) when is_map(attrs) do
    %ModelBinding{}
    |> ModelBinding.changeset(attrs)
    |> Repo.insert()
  end

  def create_profile(attrs), do: create_model_binding(attrs)

  def update_model_binding(%ModelBinding{} = binding, attrs) when is_map(attrs) do
    binding
    |> ModelBinding.changeset(attrs)
    |> Repo.update()
  end

  def update_profile(%ModelBinding{} = profile, attrs), do: update_model_binding(profile, attrs)

  def delete_model_binding(%ModelBinding{} = binding), do: Repo.delete(binding)

  def list_providers do
    Provider
    |> order_by([provider], asc: provider.key)
    |> Repo.all()
  end

  def get_provider_by_key(key) when is_binary(key), do: Repo.get_by(Provider, key: key)

  def change_provider(%Provider{} = provider, attrs \\ %{}) do
    Provider.changeset(provider, attrs)
  end

  def create_provider(attrs) when is_map(attrs) do
    %Provider{}
    |> Provider.changeset(attrs)
    |> Repo.insert()
  end

  def list_tokens(%ModelBinding{id: binding_id}) do
    Token
    |> where([token], token.model_binding_id == ^binding_id)
    |> order_by([token], desc: token.inserted_at)
    |> Repo.all()
  end

  def usage_summary(
        %ModelBinding{} = binding,
        {%DateTime{} = start_datetime, %DateTime{} = end_datetime}
      ) do
    Usage
    |> where([usage], usage.model_binding_id == ^binding.id)
    |> where([usage], usage.inserted_at >= ^start_datetime and usage.inserted_at <= ^end_datetime)
    |> select([usage], %{
      request_count: count(usage.id),
      input_tokens: coalesce(sum(usage.input_tokens), 0),
      output_tokens: coalesce(sum(usage.output_tokens), 0),
      total_tokens: coalesce(sum(usage.total_tokens), 0),
      cost_usd: coalesce(sum(usage.cost_usd), type(^Decimal.new(0), :decimal))
    })
    |> Repo.one()
    |> normalize_usage_summary()
  end

  def usage_summary(%Token{} = token, {%DateTime{} = start_datetime, %DateTime{} = end_datetime}) do
    Usage
    |> where([usage], usage.token_id == ^token.id)
    |> where([usage], usage.inserted_at >= ^start_datetime and usage.inserted_at <= ^end_datetime)
    |> select([usage], %{
      request_count: count(usage.id),
      input_tokens: coalesce(sum(usage.input_tokens), 0),
      output_tokens: coalesce(sum(usage.output_tokens), 0),
      total_tokens: coalesce(sum(usage.total_tokens), 0),
      cost_usd: coalesce(sum(usage.cost_usd), type(^Decimal.new(0), :decimal))
    })
    |> Repo.one()
    |> normalize_usage_summary()
  end

  def usage_series(subject, period, bucket \\ :day)

  def usage_series(
        %ModelBinding{} = binding,
        {%DateTime{} = start_datetime, %DateTime{} = end_datetime},
        bucket
      ) do
    Usage
    |> where([usage], usage.model_binding_id == ^binding.id)
    |> usage_series_query({start_datetime, end_datetime}, bucket)
  end

  def usage_series(
        %Token{} = token,
        {%DateTime{} = start_datetime, %DateTime{} = end_datetime},
        bucket
      ) do
    Usage
    |> where([usage], usage.token_id == ^token.id)
    |> usage_series_query({start_datetime, end_datetime}, bucket)
  end

  def token_usage_summaries(
        %ModelBinding{} = binding,
        {%DateTime{} = start_datetime, %DateTime{} = end_datetime}
      ) do
    Usage
    |> where([usage], usage.model_binding_id == ^binding.id)
    |> where([usage], usage.inserted_at >= ^start_datetime and usage.inserted_at <= ^end_datetime)
    |> group_by([usage], usage.token_id)
    |> select([usage], {
      usage.token_id,
      %{
        request_count: count(usage.id),
        input_tokens: coalesce(sum(usage.input_tokens), 0),
        output_tokens: coalesce(sum(usage.output_tokens), 0),
        total_tokens: coalesce(sum(usage.total_tokens), 0),
        cost_usd: coalesce(sum(usage.cost_usd), type(^Decimal.new(0), :decimal))
      }
    })
    |> Repo.all()
    |> Map.new(fn {token_id, summary} -> {token_id, normalize_usage_summary(summary)} end)
  end

  def create_token(%ModelBinding{} = binding, attrs) when is_map(attrs) do
    token_value = generate_token()

    attrs =
      attrs
      |> normalize_token_attrs()
      |> Map.put(:model_binding_id, binding.id)
      |> Map.put(:token_hash, hash_token(token_value))

    %Token{}
    |> Token.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, token} -> {:ok, {token, token_value}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def create_profile_token(%ModelBinding{} = profile, attrs), do: create_token(profile, attrs)

  def revoke_token(%Token{} = token) do
    token
    |> Token.changeset(%{enabled: false})
    |> Repo.update()
  end

  def authenticate_token(token_value) when is_binary(token_value) do
    token_hash = hash_token(token_value)

    Token
    |> where([token], token.token_hash == ^token_hash and token.enabled == true)
    |> preload(:model_binding)
    |> Repo.one()
    |> case do
      %Token{model_binding: %ModelBinding{enabled: true}} = token ->
        if expired?(token) do
          :error
        else
          touch_token(token)
          {:ok, token}
        end

      _other ->
        :error
    end
  end

  def authenticate_token(_token_value), do: :error

  def model_allowed?(binding, requested_model, provider_id \\ "hive")

  def model_allowed?(%ModelBinding{name: name}, requested_model, provider_id)
      when is_binary(requested_model) do
    requested_model in [name, "#{provider_id}/#{name}"]
  end

  def model_allowed?(_binding, _requested_model, _provider_id), do: false

  def relay_request(%ModelBinding{} = binding, body, opts \\ []) when is_map(body) do
    with {:ok, upstream} <- upstream_for(binding, opts) do
      {:ok,
       [
         method: :post,
         url: upstream_url(upstream.base_url, "chat/completions"),
         headers: upstream_headers(upstream, stream?(body)),
         json: Map.put(body, "model", ModelIdentifier.upstream_model(binding.upstream_model)),
         receive_timeout: upstream.timeout
       ]}
    end
  end

  def touch_model_binding(%ModelBinding{id: id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    ModelBinding
    |> where([binding], binding.id == ^id)
    |> Repo.update_all(set: [last_used_at: now, updated_at: now])

    :ok
  end

  def record_usage(%ModelBinding{} = binding, %Token{} = token, response, usage_payload \\ nil) do
    usage = response_usage(response, usage_payload)
    input_tokens = Map.fetch!(usage, :input_tokens)
    output_tokens = Map.fetch!(usage, :output_tokens)

    attrs = %{
      model_binding_id: binding.id,
      token_id: token.id,
      upstream_provider: binding.upstream_provider,
      upstream_model: binding.upstream_model,
      status: response_status(response),
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: Map.fetch!(usage, :total_tokens),
      cost_usd: usage_cost_usd(binding, input_tokens, output_tokens)
    }

    %Usage{}
    |> Usage.changeset(attrs)
    |> Repo.insert()
  end

  def response_usage(response, fallback \\ nil) do
    response
    |> response_body()
    |> usage_from_body()
    |> case do
      nil -> usage_from_body(fallback)
      usage -> usage
    end
    |> normalize_usage()
  end

  def usage_from_stream_chunk(data) when is_binary(data) do
    data
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "data:"))
    |> Enum.map(&String.trim_leading(&1, "data:"))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "[DONE]"]))
    |> Enum.find_value(fn payload ->
      case Jason.decode(payload) do
        {:ok, body} -> usage_from_body(body)
        {:error, _error} -> nil
      end
    end)
  end

  def usage_from_stream_chunk(_data), do: nil

  def config do
    Process.get(@config_key) || Application.get_env(:hive, :inference, [])
  end

  @doc false
  def put_process_config(config), do: Process.put(@config_key, config)

  @doc false
  def delete_process_config, do: Process.delete(@config_key)

  def request_fun(conf \\ config()) do
    Keyword.get(conf, :request, &Req.request/1)
  end

  def list_provider_configs do
    environment_provider_configs =
      config()
      |> Keyword.get(:providers, %{})
      |> provider_config_entries()
      |> Map.new(fn {id, provider} -> {id, provider_config(id, provider)} end)

    database_provider_configs =
      list_providers()
      |> Map.new(fn provider -> {provider.key, provider_config(provider)} end)

    configured_providers = Map.merge(environment_provider_configs, database_provider_configs)

    profile_counts = provider_profile_counts()

    configured_providers
    |> Map.merge(
      profile_counts
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(configured_providers, &1))
      |> Map.new(&{&1, missing_provider_config(&1)})
    )
    |> Enum.map(fn {id, provider} ->
      provider
      |> Map.put(:id, id)
      |> Map.put(:profile_count, Map.get(profile_counts, id, 0))
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp normalize_usage_summary(nil) do
    %{
      request_count: 0,
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      cost_usd: Decimal.new(0)
    }
  end

  defp normalize_usage_summary(summary) do
    %{
      request_count: integer_value(summary.request_count),
      input_tokens: integer_value(summary.input_tokens),
      output_tokens: integer_value(summary.output_tokens),
      total_tokens: integer_value(summary.total_tokens),
      cost_usd: decimal_value(summary.cost_usd)
    }
  end

  defp usage_series_query(query, {start_datetime, end_datetime}, bucket) do
    bucket_name = usage_bucket_name(bucket)

    rows =
      query
      |> where(
        [usage],
        usage.inserted_at >= ^start_datetime and usage.inserted_at <= ^end_datetime
      )
      |> group_by([_usage], fragment("1"))
      |> select([usage], %{
        bucket:
          type(
            fragment("date_trunc(?, ?)", ^bucket_name, usage.inserted_at),
            :utc_datetime
          ),
        request_count: count(usage.id),
        input_tokens: coalesce(sum(usage.input_tokens), 0),
        output_tokens: coalesce(sum(usage.output_tokens), 0),
        total_tokens: coalesce(sum(usage.total_tokens), 0),
        cost_usd: coalesce(sum(usage.cost_usd), type(^Decimal.new(0), :decimal))
      })
      |> Repo.all()
      |> Map.new(fn row ->
        bucket_start = row.bucket |> normalize_bucket_datetime() |> bucket_start(bucket)
        {bucket_key(bucket_start), Map.put(normalize_usage_summary(row), :bucket, bucket_start)}
      end)

    start_datetime
    |> bucket_start(bucket)
    |> buckets_until(bucket_start(end_datetime, bucket), bucket)
    |> Enum.map(fn bucket_start ->
      Map.get(
        rows,
        bucket_key(bucket_start),
        Map.put(normalize_usage_summary(nil), :bucket, bucket_start)
      )
    end)
  end

  defp usage_bucket_name(:hour), do: "hour"
  defp usage_bucket_name(:month), do: "month"
  defp usage_bucket_name(_bucket), do: "day"

  defp bucket_start(%DateTime{} = datetime, :hour) do
    %{DateTime.truncate(datetime, :second) | minute: 0, second: 0, microsecond: {0, 0}}
  end

  defp bucket_start(%DateTime{} = datetime, :month) do
    datetime
    |> DateTime.to_date()
    |> Date.beginning_of_month()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp bucket_start(%DateTime{} = datetime, _bucket) do
    datetime
    |> DateTime.to_date()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp buckets_until(start_datetime, end_datetime, bucket) do
    start_datetime
    |> Stream.iterate(&next_bucket(&1, bucket))
    |> Enum.take_while(&(DateTime.compare(&1, end_datetime) != :gt))
  end

  defp next_bucket(%DateTime{} = datetime, :hour), do: DateTime.add(datetime, 1, :hour)
  defp next_bucket(%DateTime{} = datetime, :day), do: DateTime.add(datetime, 1, :day)

  defp next_bucket(%DateTime{} = datetime, :month) do
    datetime
    |> DateTime.to_date()
    |> Date.add(32)
    |> Date.beginning_of_month()
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp next_bucket(%DateTime{} = datetime, _bucket), do: next_bucket(datetime, :day)

  defp bucket_key(%DateTime{} = datetime), do: DateTime.to_unix(datetime)

  defp normalize_bucket_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  defp normalize_bucket_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp tokens_query do
    Token
    |> order_by([token], desc: token.inserted_at)
  end

  defp upstream_for(%ModelBinding{upstream_provider: provider_id}, opts) do
    conf = Keyword.get(opts, :config, config())

    with {:ok, provider} <- resolve_provider(conf, provider_id),
         {:ok, base_url} <- required_provider_value(provider, :base_url) do
      {:ok,
       %{
         id: provider_id,
         base_url: String.trim_trailing(base_url, "/"),
         api_key: provider_value(provider, :api_key),
         timeout: provider_timeout(provider)
       }}
    end
  end

  defp resolve_provider(conf, provider_id) do
    case get_provider_by_key(provider_id) do
      %Provider{} = provider ->
        {:ok, provider_runtime_config(provider)}

      nil ->
        conf
        |> Keyword.get(:providers, %{})
        |> find_provider(provider_id)
    end
  end

  defp provider_runtime_config(%Provider{} = provider) do
    %{
      id: provider.key,
      base_url: provider.base_url,
      api_key: Provider.api_key(provider),
      timeout: provider.timeout
    }
  end

  defp find_provider(providers, provider_id) when is_map(providers) do
    providers
    |> Enum.find_value(fn {key, provider} ->
      if to_string(key) == provider_id, do: provider
    end)
    |> case do
      nil -> {:error, :upstream_not_configured}
      provider -> {:ok, provider}
    end
  end

  defp find_provider(providers, provider_id) when is_list(providers) do
    providers
    |> Enum.find_value(fn
      {key, provider} ->
        if to_string(key) == provider_id, do: provider

      provider when is_map(provider) ->
        if provider_value(provider, :id) == provider_id, do: provider

      _other ->
        nil
    end)
    |> case do
      nil -> {:error, :upstream_not_configured}
      provider -> {:ok, provider}
    end
  end

  defp find_provider(_providers, _provider_id), do: {:error, :upstream_not_configured}

  defp provider_config_entries(providers) when is_map(providers) do
    providers
    |> Enum.map(fn {id, provider} -> {to_string(id), provider} end)
    |> Enum.reject(fn {id, _provider} -> blank?(id) end)
  end

  defp provider_config_entries(providers) when is_list(providers) do
    providers
    |> Enum.flat_map(fn
      {id, provider} ->
        [{to_string(id), provider}]

      provider when is_map(provider) ->
        case provider_value(provider, :id) do
          id when is_binary(id) and id != "" -> [{id, provider}]
          _other -> []
        end

      _other ->
        []
    end)
    |> Enum.reject(fn {id, _provider} -> blank?(id) end)
  end

  defp provider_config_entries(_providers), do: []

  defp provider_config(id, provider) do
    base_url = provider_value(provider, :base_url)

    %{
      id: id,
      base_url: present_value(base_url),
      configured?: true,
      credential_configured?: present?(provider_value(provider, :api_key)),
      endpoint_configured?: present?(base_url),
      profile_count: 0,
      source: :environment,
      timeout: provider_timeout(provider)
    }
  end

  defp provider_config(%Provider{} = provider) do
    %{
      id: provider.key,
      base_url: provider.base_url,
      configured?: true,
      credential_configured?: Provider.credential_configured?(provider),
      endpoint_configured?: present?(provider.base_url),
      profile_count: 0,
      source: :database,
      timeout: provider.timeout
    }
  end

  defp missing_provider_config(id) do
    %{
      id: id,
      base_url: nil,
      configured?: false,
      credential_configured?: false,
      endpoint_configured?: false,
      profile_count: 0,
      source: :reference,
      timeout: nil
    }
  end

  defp provider_profile_counts do
    ModelBinding
    |> group_by([binding], binding.upstream_provider)
    |> select([binding], {binding.upstream_provider, count(binding.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp required_provider_value(provider, key) do
    case provider_value(provider, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, :upstream_not_configured}
    end
  end

  defp provider_value(provider, key) when is_map(provider) do
    Map.get(provider, key) || Map.get(provider, to_string(key))
  end

  defp provider_value(provider, key) when is_list(provider) do
    string_key = to_string(key)

    Enum.find_value(provider, fn
      {entry_key, value} when entry_key == key -> value
      {entry_key, value} -> if to_string(entry_key) == string_key, do: value
      _entry -> nil
    end)
  end

  defp provider_value(_provider, _key), do: nil

  defp provider_timeout(provider) do
    case provider_value(provider, :timeout) do
      value when is_integer(value) and value > 0 -> value
      value when is_binary(value) -> parse_positive_integer(value, 300_000)
      _other -> 300_000
    end
  end

  defp parse_positive_integer(value, default) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _other -> default
    end
  end

  defp present_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_value(value), do: value

  defp present?(value), do: not blank?(value)

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp upstream_url(base_url, path), do: "#{base_url}/#{path}"

  defp usage_cost_usd(%ModelBinding{} = binding, input_tokens, output_tokens) do
    provider =
      config()
      |> resolve_provider(binding.upstream_provider)
      |> case do
        {:ok, provider} -> provider
        {:error, _reason} -> %{}
      end

    price = price_for_model(provider, binding.upstream_model)

    input_cost =
      input_tokens
      |> token_cost(model_binding_price(binding, price, provider, :input_cost_per_million))

    output_cost =
      output_tokens
      |> token_cost(model_binding_price(binding, price, provider, :output_cost_per_million))

    input_cost
    |> Decimal.add(output_cost)
    |> Decimal.round(9)
  end

  defp price_for_model(provider, model) do
    provider
    |> provider_value(:prices)
    |> price_for_model(model, ModelIdentifier.upstream_model(model))
  end

  defp price_for_model(prices, model, upstream_model) when is_map(prices) or is_list(prices) do
    Enum.find_value([model, upstream_model, :default], &provider_value(prices, &1)) || %{}
  end

  defp price_for_model(_prices, _model, _upstream_model), do: %{}

  defp model_binding_price(binding, price, provider, field) do
    Map.get(binding, field) ||
      provider_value(price, field) ||
      provider_value(price, legacy_price_field(field)) ||
      provider_value(provider, field) ||
      provider_value(provider, legacy_price_field(field)) ||
      Decimal.new(0)
  end

  defp legacy_price_field(:input_cost_per_million), do: :input_token_cost_per_million
  defp legacy_price_field(:output_cost_per_million), do: :output_token_cost_per_million

  defp token_cost(tokens, price_per_million) do
    tokens
    |> integer_value()
    |> Decimal.new()
    |> Decimal.mult(decimal_value(price_per_million))
    |> Decimal.div(Decimal.new(1_000_000))
  end

  defp upstream_headers(%{api_key: api_key}, streamed?) do
    [
      {"content-type", "application/json"},
      {"accept", if(streamed?, do: "text/event-stream", else: "application/json")}
    ]
    |> maybe_put_authorization(api_key)
  end

  defp maybe_put_authorization(headers, api_key) when is_binary(api_key) and api_key != "" do
    [{"authorization", "Bearer #{api_key}"} | headers]
  end

  defp maybe_put_authorization(headers, _api_key), do: headers

  defp stream?(%{"stream" => true}), do: true
  defp stream?(%{stream: true}), do: true
  defp stream?(_body), do: false

  defp response_status(%{status: status}) when is_integer(status), do: status
  defp response_status(_response), do: 200

  defp response_body(%{body: body}), do: body
  defp response_body(_response), do: nil

  defp usage_from_body(%{"usage" => usage}) when is_map(usage), do: normalize_usage(usage)
  defp usage_from_body(%{usage: usage}) when is_map(usage), do: normalize_usage(usage)
  defp usage_from_body(_body), do: nil

  defp normalize_usage(nil), do: normalize_usage(%{})

  defp normalize_usage(usage) when is_map(usage) do
    input_tokens =
      usage
      |> usage_integer_value(["prompt_tokens", :prompt_tokens, "input_tokens", :input_tokens])

    output_tokens =
      usage
      |> usage_integer_value([
        "completion_tokens",
        :completion_tokens,
        "output_tokens",
        :output_tokens
      ])

    total_tokens =
      usage
      |> usage_integer_value(["total_tokens", :total_tokens])
      |> case do
        0 -> input_tokens + output_tokens
        value -> value
      end

    %{input_tokens: input_tokens, output_tokens: output_tokens, total_tokens: total_tokens}
  end

  defp normalize_usage(_usage), do: normalize_usage(%{})

  defp usage_integer_value(usage, keys) do
    Enum.find_value(keys, 0, fn key ->
      case Map.get(usage, key) do
        value when is_integer(value) and value >= 0 -> value
        value when is_binary(value) -> parse_non_negative_integer(value)
        _value -> nil
      end
    end)
  end

  defp parse_non_negative_integer(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _other -> nil
    end
  end

  defp normalize_token_attrs(attrs) do
    attrs
    |> Enum.reduce(%{}, fn
      {key, value}, acc when is_binary(key) ->
        case Map.fetch(@token_attr_key_map, key) do
          {:ok, attr} -> Map.put(acc, attr, value)
          :error -> acc
        end

      {key, value}, acc when key in @token_attr_keys ->
        Map.put(acc, key, value)

      _entry, acc ->
        acc
    end)
  end

  defp expired?(%Token{expires_at: nil}), do: false

  defp expired?(%Token{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  defp touch_token(%Token{id: id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Token
    |> where([token], token.id == ^id)
    |> Repo.update_all(set: [last_used_at: now, updated_at: now])

    :ok
  end

  defp generate_token do
    @token_prefix <>
      (@token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
  end

  defp hash_token(token) do
    :sha256
    |> :crypto.hash(token)
    |> Base.encode16(case: :lower)
  end

  defp integer_value(nil), do: 0
  defp integer_value(value) when is_integer(value), do: value

  defp integer_value(%Decimal{} = value) do
    value
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp decimal_value(%Decimal{} = value), do: value
  defp decimal_value(nil), do: Decimal.new(0)
  defp decimal_value(value) when is_integer(value), do: Decimal.new(value)

  defp decimal_value(value) when is_float(value) do
    value
    |> Float.to_string()
    |> Decimal.new()
  end

  defp decimal_value(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      _other -> Decimal.new(0)
    end
  end

  defp decimal_value(_value), do: Decimal.new(0)
end
