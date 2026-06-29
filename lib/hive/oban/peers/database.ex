defmodule Hive.Oban.Peers.Database do
  @moduledoc """
  Database-backed Oban peer that preserves leadership through transient connection failures.

  This intentionally mirrors `Oban.Peers.Database` from Oban 2.23, with the smallest local
  difference needed to avoid terminating the peer process when an election transaction exhausts
  its retry budget after a transient connection failure.

  Remove this module and return to the built-in Oban peer once Oban handles exhausted database
  peer election retries without terminating the peer process.
  """

  @behaviour Oban.Peer

  use GenServer

  import Ecto.Query, only: [select: 3, where: 2, where: 3]

  alias Oban.{Backoff, Notifier}
  alias __MODULE__, as: State

  defstruct [
    :conf,
    :timer,
    interval: :timer.seconds(30),
    leader?: false,
    leader_boost: 2,
    repo: Oban.Repo
  ]

  @doc false
  def child_spec(opts), do: super(opts)

  @impl Oban.Peer
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, struct!(State, opts), name: name)
  end

  @impl Oban.Peer
  def leader?(pid, timeout \\ 5_000) do
    GenServer.call(pid, :leader?, timeout)
  end

  @impl Oban.Peer
  def get_leader(pid, timeout \\ 5_000) do
    GenServer.call(pid, :get_leader, timeout)
  end

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)

    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def terminate(_reason, %State{timer: timer} = state) do
    if is_reference(timer), do: Process.cancel_timer(timer)

    if state.leader? do
      fun = fn ->
        delete_self(state)
        notify_down(state)
      end

      try do
        state.repo.transaction(state.conf, fun, retry: 1, on_exhausted: :log)
      catch
        :exit, _reason -> :ok
      end
    end

    :ok
  end

  @impl GenServer
  def handle_continue(:start, %State{} = state) do
    Notifier.listen(state.conf.name, :leader)

    handle_info(:election, state)
  end

  @impl GenServer
  def handle_info(:election, %State{} = state) do
    meta = %{conf: state.conf, leader: state.leader?, peer: __MODULE__, was_leader: nil}

    state =
      :telemetry.span([:oban, :peer, :election], meta, fn ->
        fun = fn ->
          state
          |> delete_expired_peers()
          |> attempt_leadership()
        end

        case state.repo.transaction(state.conf, fun, retry: 1, on_exhausted: :log) do
          {:ok, state} ->
            {state, %{meta | leader: state.leader?, was_leader: meta.leader}}

          {:error, _reason} ->
            {state, %{meta | was_leader: meta.leader}}
        end
      end)

    {:noreply, schedule_election(state)}
  end

  def handle_info({:notification, :leader, %{"down" => name}}, %State{conf: conf} = state) do
    if name == inspect(conf.name) do
      handle_info(:election, state)
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:election, _from, %State{} = state) do
    {:noreply, state} = handle_info(:election, state)

    {:reply, state, state}
  end

  def handle_call(:leader?, _from, %State{} = state) do
    {:reply, state.leader?, state}
  end

  def handle_call(:get_leader, _from, %State{conf: conf} = state) do
    {:reply, query_leader(state.repo, conf), state}
  end

  defp schedule_election(%State{interval: interval} = state) do
    base = if state.leader?, do: div(interval, state.leader_boost), else: interval
    time = Backoff.jitter(base, mode: :dec)

    %{state | timer: Process.send_after(self(), :election, time)}
  end

  defp delete_expired_peers(%State{conf: conf, repo: repo} = state) do
    query =
      "oban_peers"
      |> where([p], p.name == ^inspect(conf.name))
      |> where([p], p.expires_at < ^DateTime.utc_now())

    repo.delete_all(conf, query)

    state
  end

  defp delete_self(%State{conf: conf, repo: repo}) do
    query = where("oban_peers", name: ^inspect(conf.name), node: ^conf.node)

    repo.delete_all(conf, query)
  end

  defp query_leader(repo, conf) do
    query =
      "oban_peers"
      |> where([p], p.name == ^inspect(conf.name))
      |> select([p], p.node)

    repo.one(conf, query)
  end

  defp attempt_leadership(%State{conf: conf} = state) do
    started_at = DateTime.utc_now()
    expires_at = DateTime.add(started_at, state.interval, :millisecond)

    peer_data = %{
      name: inspect(conf.name),
      node: conf.node,
      started_at: started_at,
      expires_at: expires_at
    }

    leader? =
      if state.conf.engine == Oban.Engines.Dolphin do
        dolphin_insert(peer_data, state)
      else
        regular_upsert(peer_data, state)
      end

    %{state | leader?: leader?}
  end

  defp regular_upsert(peer_data, state) do
    repo_opts =
      if state.leader? do
        [conflict_target: :name, on_conflict: [set: [expires_at: peer_data.expires_at]]]
      else
        [conflict_target: :name, on_conflict: :nothing]
      end

    case state.repo.insert_all(state.conf, "oban_peers", [peer_data], repo_opts) do
      {0, nil} -> false
      {_, nil} -> true
    end
  end

  defp dolphin_insert(peer_data, state) do
    repo_opts =
      if state.leader? do
        [on_conflict: [set: [expires_at: peer_data.expires_at]]]
      else
        [on_conflict: :nothing]
      end

    state.repo.insert_all(state.conf, "oban_peers", [peer_data], repo_opts)

    query_leader(state.repo, state.conf) == peer_data.node
  end

  defp notify_down(%State{conf: conf}) do
    Notifier.notify(conf, :leader, %{down: inspect(conf.name)})
  end
end
