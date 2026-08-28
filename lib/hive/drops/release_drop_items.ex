defmodule Hive.Drops.ReleaseDropItems do
  @moduledoc """
  Builds bounded GitHub issue evidence for the release drop item agent and
  normalizes its structured output before the syncer persists anything.
  """

  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.Domains.GitHubRepository
  alias Hive.Drops.Agents.ReleaseDropItemAgent
  alias Hive.GitHub.IssueRefs
  alias Hive.GitHub.Issues
  alias Hive.GitHub.Releases
  alias Hive.Repo
  alias Hive.URL

  @max_release_body_length 6_000
  @max_references 6
  @max_reference_body_length 2_000
  @max_items 6

  @doc """
  Generates individual, user-facing drop items for a GitHub release.

  Hive supplies only the release notes and directly referenced GitHub issues
  or pull requests. It never follows arbitrary links in the release body.
  Returns `:skipped` when agents are disabled or the model is not configured.
  """
  def generate(%GitHubRepository{} = repository, %Releases{} = release, opts \\ []) do
    if agents_enabled?(opts) do
      generate_from_references(repository, release, opts)
    else
      :skipped
    end
  end

  defp generate_from_references(repository, release, opts) do
    case fetch_references(repository, release, opts) do
      [] ->
        {:ok, []}

      references ->
        repository
        |> build_input(release, references)
        |> then(fn input -> {input, run_generator(input, opts)} end)
        |> then(fn {input, result} -> handle_agent_result(result, input) end)
    end
  end

  def build_input(%GitHubRepository{} = repository, %Releases{} = release, references \\ []) do
    %{
      release: %{
        repository: "#{repository.owner}/#{repository.name}",
        tag: release.tag_name || "",
        title: release.name || "",
        body: truncate(release.body || "", @max_release_body_length),
        url: release.html_url || "",
        published_at: release.published_at || release.created_at || "",
        references: Enum.take(references, @max_references)
      }
    }
  end

  defp fetch_references(repository, release, opts) do
    issue_fetcher = Keyword.get(opts, :issue_fetcher, &Issues.get_issue/2)

    release
    |> issue_refs(repository)
    |> Enum.flat_map(fn ref -> fetch_reference(ref, repository, issue_fetcher) end)
  end

  defp issue_refs(release, repository) do
    (release.body || "")
    |> IssueRefs.extract(
      default_repo: {repository.owner, repository.name},
      limit: @max_references
    )
  end

  defp fetch_reference(ref, source_repository, issue_fetcher) do
    with %GitHubRepository{} = repository <- repository_for_ref(ref, source_repository),
         {:ok, issue} <- issue_fetcher.(repository, ref.number),
         reference when not is_nil(reference) <- reference_from_issue(issue, ref) do
      [reference]
    else
      _ -> []
    end
  end

  defp repository_for_ref(ref, %GitHubRepository{owner: owner, name: name} = repository) do
    if ref.owner == owner and ref.name == name do
      repository
    else
      Repo.get_by(GitHubRepository, owner: ref.owner, name: ref.name)
    end
  end

  defp reference_from_issue(issue, ref) do
    url =
      issue
      |> get_value(:html_url)
      |> clean_url()
      |> case do
        nil -> "https://github.com/#{ref.owner}/#{ref.name}/issues/#{ref.number}"
        value -> value
      end

    if public_url?(url) do
      %{
        url: url,
        number: ref.number,
        title: issue |> get_value(:title) |> clean_text() || "",
        body: issue |> get_value(:body) |> clean_text() |> truncate(@max_reference_body_length),
        state: issue |> get_value(:state) |> normalize_state()
      }
    end
  end

  defp run_generator(input, opts) do
    runner = Keyword.get(opts, :runner, &run_agent(&1, opts))
    runner.(input)
  end

  defp run_agent(input, opts) do
    agent = Keyword.get(opts, :agent, ReleaseDropItemAgent)
    agent_opts = opts |> Keyword.get(:agent_opts, []) |> Keyword.put(:max_turns, 1)

    Sessions.run_operation(agent, :generate_drop_items, input, agent_opts)
  end

  defp handle_agent_result({:ok, %{items: items}}, input),
    do: {:ok, normalize_items(items, allowed_source_urls(input))}

  defp handle_agent_result({:ok, %{"items" => items}}, input),
    do: {:ok, normalize_items(items, allowed_source_urls(input))}

  defp handle_agent_result({:error, :llm_not_configured}, _input), do: :skipped
  defp handle_agent_result(other, _input), do: other

  defp normalize_items(items, allowed_urls) when is_list(items) do
    items
    |> Enum.map(&normalize_item(&1, allowed_urls))
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@max_items)
  end

  defp normalize_items(_items, _allowed_urls), do: []

  defp normalize_item(item, allowed_urls) when is_map(item) do
    title = item |> get_value(:title) |> clean_text()
    body = item |> get_value(:body) |> clean_text()
    source_urls = item |> get_value(:source_urls) |> normalize_source_urls(allowed_urls)

    if title && body && source_urls != [] do
      %{title: title, body: body, source_urls: source_urls}
    end
  end

  defp normalize_item(_item, _allowed_urls), do: nil

  defp normalize_source_urls(urls, allowed_urls) when is_list(urls) do
    urls
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&clean_url/1)
    |> Enum.filter(&(public_url?(&1) and &1 in allowed_urls))
    |> Enum.uniq()
    |> Enum.take(@max_references)
  end

  defp normalize_source_urls(url, allowed_urls) when is_binary(url),
    do: normalize_source_urls([url], allowed_urls)

  defp normalize_source_urls(_urls, _allowed_urls), do: []

  defp allowed_source_urls(%{release: release}) do
    [release.url | Enum.map(release.references, & &1.url)]
    |> Enum.map(&clean_url/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_state(state) when is_atom(state), do: Atom.to_string(state)
  defp normalize_state(state) when is_binary(state), do: state
  defp normalize_state(_state), do: ""

  defp clean_url(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_trailing(".")
    |> String.trim_trailing(",")
    |> String.trim_trailing(";")
    |> String.trim_trailing(":")
    |> case do
      "" -> nil
      url -> url
    end
  end

  defp clean_url(_value), do: nil

  defp public_url?(url) when is_binary(url), do: match?({:ok, _uri}, URL.validate_public(url))
  defp public_url?(_url), do: false

  defp get_value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp clean_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp clean_text(_value), do: nil

  defp agents_enabled?(opts) do
    fun = Keyword.get(opts, :agents_enabled?, &Agents.enabled?/0)
    fun.()
  end

  defp truncate(nil, _limit), do: ""

  defp truncate(value, limit) when is_binary(value) do
    if String.length(value) > limit, do: String.slice(value, 0, limit), else: value
  end
end
