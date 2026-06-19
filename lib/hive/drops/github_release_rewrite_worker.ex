defmodule Hive.Drops.GitHubReleaseRewriteWorker do
  @moduledoc """
  Runs the user-facing rewrite of a GitHub release body asynchronously
  so the syncer doesn't have to wait for the LLM. Jobs are de-duplicated
  per drop while they sit in the queue.
  """

  use Oban.Worker,
    queue: :agents,
    max_attempts: 3,
    unique: [fields: [:worker, :queue, :args], period: :infinity, states: :incomplete]

  require Logger

  alias Hive.Drops
  alias Hive.Drops.Drop
  alias Hive.Drops.ReleaseBodyRewriter

  @doc """
  Enqueues a rewrite job for the given drop. Returns `:skipped` when
  agentic workflows are dormant or when the drop doesn't need rewriting.
  """
  def enqueue(drop, opts \\ [])

  def enqueue(%Drop{} = drop, opts) do
    agents_enabled? = Keyword.get(opts, :agents_enabled?, &Hive.Agents.enabled?/0)

    cond do
      not agents_enabled?.() ->
        :skipped

      drop.source_type != :github_release ->
        :skipped

      is_nil(drop.raw_body) or drop.raw_body == "" ->
        :skipped

      not is_nil(drop.rewritten_at) ->
        :skipped

      true ->
        %{"drop_id" => drop.id}
        |> new()
        |> Oban.insert()
    end
  end

  def enqueue(_other, _opts), do: :skipped

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"drop_id" => drop_id}}) do
    case Drops.get_drop(drop_id) do
      nil ->
        Logger.info("[Drops.GitHubReleaseRewriteWorker] Drop #{drop_id} no longer exists")

        :ok

      %Drop{} = drop ->
        case ReleaseBodyRewriter.rewrite(drop) do
          {:ok, _outcome} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
