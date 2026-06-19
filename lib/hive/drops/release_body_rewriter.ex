defmodule Hive.Drops.ReleaseBodyRewriter do
  @moduledoc """
  Orchestrates the user-facing rewrite of a GitHub-release-sourced drop.

  Hands the agent the raw release body plus the `fetch_url_content`
  Condukt tool; the agent navigates the issues, pull requests, and
  other links the body cites and produces the markdown the drop will
  display.
  """

  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.Drops
  alias Hive.Drops.Agents.ReleaseRewriterAgent
  alias Hive.Drops.Drop
  alias Hive.Meadows.GitHubRepository

  @max_body_chars 16_000

  @doc """
  Rewrites `drop`'s body when the LLM is configured and the drop is a
  GitHub release with a non-empty raw body. Otherwise returns
  `{:ok, :skipped}` and leaves the drop alone so the dashboard keeps
  showing the original release notes.
  """
  def rewrite(%Drop{} = drop, opts \\ []) do
    cond do
      not Agents.enabled?() -> {:ok, :skipped}
      drop.source_type != :github_release -> {:ok, :skipped}
      blank?(drop.raw_body) -> {:ok, :skipped}
      not is_nil(drop.rewritten_at) -> {:ok, :skipped}
      true -> do_rewrite(drop, opts)
    end
  end

  defp do_rewrite(drop, opts) do
    drop = Hive.Repo.preload(drop, [:meadows, :github_repository])
    input = build_input(drop)
    runner = Keyword.get(opts, :runner, &run_agent(&1, opts))

    input
    |> runner.()
    |> handle_agent_result(drop)
  end

  defp handle_agent_result({:ok, %{body: body}}, drop)
       when is_binary(body) and body != "" do
    Drops.mark_rewritten(drop, body)
  end

  defp handle_agent_result({:ok, _other}, _drop), do: {:error, :invalid_agent_response}
  defp handle_agent_result({:error, :llm_not_configured}, _drop), do: {:ok, :skipped}
  defp handle_agent_result({:error, reason}, _drop), do: {:error, reason}

  defp build_input(drop) do
    meadows = drop.meadows || []

    %{
      meadow: %{
        name: Enum.map_join(meadows, ", ", & &1.name),
        description:
          meadows |> Enum.map(& &1.description) |> Enum.reject(&is_nil/1) |> Enum.join(" / ")
      },
      repository: repository_label(drop.github_repository),
      release: %{
        tag: release_tag(drop),
        name: drop.title || "",
        url: drop.url || "",
        body: truncate(drop.raw_body, @max_body_chars)
      }
    }
  end

  defp run_agent(input, opts) do
    agent = Keyword.get(opts, :agent, ReleaseRewriterAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run_operation(agent, :rewrite_release, input, agent_opts)
  end

  defp repository_label(%GitHubRepository{owner: owner, name: name}), do: "#{owner}/#{name}"
  defp repository_label(_other), do: ""

  defp release_tag(%Drop{external_id: ext}) when is_binary(ext) do
    case String.split(ext, "@", parts: 2) do
      [_repo, tag] -> tag
      _ -> ext
    end
  end

  defp release_tag(_other), do: ""

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_other), do: true

  defp truncate(nil, _max), do: ""

  defp truncate(value, max) when is_binary(value) and byte_size(value) > max,
    do: binary_part(value, 0, max)

  defp truncate(value, _max), do: value
end
