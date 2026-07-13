defmodule Hive.Drops.ReleaseDropItems do
  @moduledoc """
  Builds the input for the release drop item agent and normalizes its
  structured output before the syncer persists anything.
  """

  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.Agents.Tools.FetchUrlContent
  alias Hive.Drops.Agents.ReleaseDropItemAgent
  alias Hive.GitHub.IssueRefs
  alias Hive.GitHub.Releases
  alias Hive.Domains.GitHubRepository
  alias Hive.URL

  @max_release_body_length 20_000
  @max_reference_urls 40
  @max_fetched_reference_urls 50
  @fetch_concurrency 8
  @fetch_timeout 45_000
  @url_re ~r{https?://[^\s<>\]\)"]+}i

  @doc """
  Generates user-facing drop items for a GitHub release.

  Returns `:skipped` when agents are disabled or the LLM is not
  configured. Returns `{:ok, items}` with normalized maps when the agent
  succeeds.
  """
  def generate(%GitHubRepository{} = repository, %Releases{} = release, opts \\ []) do
    if agents_enabled?(opts) do
      references = fetch_references(repository, release, opts)
      input = build_input(repository, release, references)

      input
      |> run_generator(opts)
      |> handle_agent_result()
    else
      :skipped
    end
  end

  def build_input(%GitHubRepository{} = repository, %Releases{} = release, references \\ []) do
    reference_urls = reference_urls(repository, release.body || "")

    %{
      release: %{
        repository: "#{repository.owner}/#{repository.name}",
        tag: release.tag_name || "",
        title: release.name || "",
        body: truncate(release.body || ""),
        url: release.html_url || "",
        published_at: release.published_at || release.created_at || "",
        reference_urls: reference_urls,
        references: references
      }
    }
  end

  defp fetch_references(repository, release, opts) do
    seed_urls = reference_urls(repository, release.body || "")
    fetcher = Keyword.get(opts, :fetcher, &FetchUrlContent.fetch/1)

    fetch_reference_queue(seed_urls, MapSet.new(seed_urls), fetcher, [])
  end

  defp fetch_reference_queue([], _seen_urls, _fetcher, references), do: references

  defp fetch_reference_queue(urls, seen_urls, fetcher, references) do
    remaining = @max_fetched_reference_urls - length(references)
    urls = Enum.take(urls, remaining)
    fetched_references = fetch_url_batch(urls, fetcher)
    references = references ++ fetched_references
    remaining = @max_fetched_reference_urls - length(references)

    discovered_urls =
      fetched_references
      |> Enum.flat_map(&urls_from_reference/1)
      |> Enum.reject(&MapSet.member?(seen_urls, &1))
      |> Enum.uniq()
      |> Enum.take(remaining)

    seen_urls = Enum.reduce(discovered_urls, seen_urls, &MapSet.put(&2, &1))

    fetch_reference_queue(discovered_urls, seen_urls, fetcher, references)
  end

  defp fetch_url_batch([], _fetcher), do: []

  defp fetch_url_batch(urls, fetcher) do
    urls
    |> Task.async_stream(
      fn url -> normalize_fetch_result(url, fetcher.(url)) end,
      max_concurrency: @fetch_concurrency,
      ordered: true,
      on_timeout: :kill_task,
      timeout: @fetch_timeout
    )
    |> Enum.zip(urls)
    |> Enum.map(fn
      {{:ok, reference}, _url} -> reference
      {{:exit, _reason}, url} -> %{url: url, error: "The reference fetch timed out."}
    end)
  end

  defp normalize_fetch_result(url, {:ok, result}) when is_map(result) do
    %{
      url: url,
      final_url: fetch_value(result, :final_url, url),
      title: fetch_value(result, :title, ""),
      content_type: fetch_value(result, :content_type, "unknown"),
      content: fetch_value(result, :content, ""),
      truncated: fetch_value(result, :truncated, false)
    }
  end

  defp normalize_fetch_result(url, {:error, reason}) do
    %{url: url, error: fetch_error(reason)}
  end

  defp normalize_fetch_result(url, other) do
    %{url: url, error: fetch_error(other)}
  end

  defp fetch_value(result, key, default) do
    Map.get(result, key) || Map.get(result, Atom.to_string(key)) || default
  end

  defp urls_from_reference(%{content: content}) when is_binary(content),
    do: urls_from_text(content)

  defp urls_from_reference(_reference), do: []

  defp urls_from_text(text) do
    @url_re
    |> Regex.scan(text)
    |> Enum.map(fn [url] -> clean_url(url) end)
    |> Enum.filter(&public_url?/1)
  end

  defp fetch_error(reason) when is_binary(reason), do: String.slice(reason, 0, 500)
  defp fetch_error(reason), do: reason |> inspect() |> String.slice(0, 500)

  defp run_generator(input, opts) do
    runner = Keyword.get(opts, :runner, &run_agent(&1, opts))
    runner.(input)
  end

  defp run_agent(input, opts) do
    agent = Keyword.get(opts, :agent, ReleaseDropItemAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run_operation(agent, :generate_drop_items, input, agent_opts)
  end

  defp handle_agent_result({:ok, %{items: items}}), do: {:ok, normalize_items(items)}
  defp handle_agent_result({:ok, %{"items" => items}}), do: {:ok, normalize_items(items)}
  defp handle_agent_result({:error, :llm_not_configured}), do: :skipped
  defp handle_agent_result(other), do: other

  defp normalize_items(items) when is_list(items) do
    items
    |> Enum.map(&normalize_item/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_items(_items), do: []

  defp normalize_item(item) when is_map(item) do
    title = item |> get_value(:title) |> clean_text()
    body = item |> get_value(:body) |> clean_text()
    source_urls = item |> get_value(:source_urls) |> normalize_source_urls()

    if title && body && source_urls != [] do
      %{title: title, body: body, source_urls: source_urls}
    end
  end

  defp normalize_item(_item), do: nil

  defp reference_urls(%GitHubRepository{} = repository, body) do
    body_urls = urls_from_body(body)

    body_urls
    |> Kernel.++(urls_from_refs(repository, body, body_urls))
    |> Enum.uniq()
    |> Enum.take(@max_reference_urls)
  end

  defp urls_from_body(body) do
    @url_re
    |> Regex.scan(body)
    |> Enum.map(fn [url] -> clean_url(url) end)
    |> Enum.filter(&public_url?/1)
  end

  defp urls_from_refs(repository, body, body_urls) do
    body
    |> IssueRefs.extract(
      default_repo: {repository.owner, repository.name},
      limit: @max_reference_urls
    )
    |> Enum.reject(&ref_already_has_url?(&1, body_urls))
    |> Enum.map(fn ref -> "https://github.com/#{ref.owner}/#{ref.name}/issues/#{ref.number}" end)
  end

  defp ref_already_has_url?(ref, urls) do
    Enum.any?(urls, fn url ->
      case URI.parse(url) do
        %URI{host: host, path: path} when is_binary(host) and is_binary(path) ->
          host = String.downcase(host)
          path_parts = path |> String.trim_leading("/") |> String.split("/")

          host in ["github.com", "www.github.com"] and
            github_ref_path?(path_parts, ref)

        _ ->
          false
      end
    end)
  end

  defp github_ref_path?([owner, name, type, number], ref)
       when type in ["issues", "pull"] do
    String.downcase(owner) == ref.owner and String.downcase(name) == ref.name and
      Integer.to_string(ref.number) == number
  end

  defp github_ref_path?(_path_parts, _ref), do: false

  defp normalize_source_urls(urls) when is_list(urls) do
    urls
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&clean_url/1)
    |> Enum.filter(&public_url?/1)
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp normalize_source_urls(url) when is_binary(url), do: normalize_source_urls([url])
  defp normalize_source_urls(_urls), do: []

  defp clean_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim_trailing(",")
    |> String.trim_trailing(";")
    |> String.trim_trailing(":")
  end

  defp public_url?(url) when is_binary(url) do
    match?({:ok, _uri}, URL.validate_public(url))
  end

  defp public_url?(_url), do: false

  defp get_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp clean_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp clean_text(_value), do: nil

  defp agents_enabled?(opts) do
    fun = Keyword.get(opts, :agents_enabled?, &Agents.enabled?/0)
    fun.()
  end

  defp truncate(value) when is_binary(value) do
    if String.length(value) > @max_release_body_length,
      do: String.slice(value, 0, @max_release_body_length),
      else: value
  end
end
