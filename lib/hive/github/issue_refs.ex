defmodule Hive.GitHub.IssueRefs do
  @moduledoc """
  Extracts issue and pull-request references from free-form release
  bodies so the rewriter can fetch and inline their context.

  Three styles are recognised, in order of specificity:

    * `https://github.com/<owner>/<name>/issues/<number>` or
      `https://github.com/<owner>/<name>/pull/<number>`
    * `<owner>/<name>#<number>` (cross-repo shorthand)
    * `#<number>` (same-repo shorthand; needs a default repo to resolve)

  References are returned as a list of unique
  `%{owner: String.t(), name: String.t(), number: integer()}` maps,
  capped at `:limit` (default 10) to keep API usage bounded.
  """

  @default_limit 10

  @url_re ~r{https?://(?:www\.)?github\.com/([\w.-]+)/([\w.-]+)/(?:issues|pull)/(\d+)}i
  @cross_repo_re ~r{(?<![\w/])([\w.-]+)/([\w.-]+)#(\d+)}
  @same_repo_re ~r{(?<![\w/])#(\d+)}

  @doc """
  Returns up to `:limit` unique issue/PR references mentioned in
  `text`. Pass `:default_repo` (a `{owner, name}` tuple) to resolve
  bare `#N` references; without it those refs are dropped.
  """
  def extract(text, opts \\ [])

  def extract(nil, _opts), do: []

  def extract(text, opts) when is_binary(text) do
    limit = Keyword.get(opts, :limit, @default_limit)
    default_repo = Keyword.get(opts, :default_repo)

    refs =
      []
      |> capture_urls(text)
      |> capture_cross_repo(text)
      |> capture_same_repo(text, default_repo)
      |> Enum.uniq()
      |> Enum.take(limit)

    Enum.map(refs, fn {owner, name, number} ->
      %{owner: owner, name: name, number: number}
    end)
  end

  def extract(_other, _opts), do: []

  defp capture_urls(refs, text) do
    Regex.scan(@url_re, text)
    |> Enum.reduce(refs, fn [_match, owner, name, number], acc ->
      add_ref(acc, owner, name, number)
    end)
  end

  defp capture_cross_repo(refs, text) do
    Regex.scan(@cross_repo_re, text)
    |> Enum.reduce(refs, fn [_match, owner, name, number], acc ->
      add_ref(acc, owner, name, number)
    end)
  end

  defp capture_same_repo(refs, _text, nil), do: refs

  defp capture_same_repo(refs, text, {owner, name})
       when is_binary(owner) and is_binary(name) do
    Regex.scan(@same_repo_re, text)
    |> Enum.reduce(refs, fn [_match, number], acc ->
      add_ref(acc, owner, name, number)
    end)
  end

  defp add_ref(refs, owner, name, number) do
    case parse_number(number) do
      {:ok, n} -> refs ++ [{String.downcase(owner), String.downcase(name), n}]
      :error -> refs
    end
  end

  defp parse_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end
end
