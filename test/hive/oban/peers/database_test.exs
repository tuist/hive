defmodule Hive.Oban.Peers.DatabaseTest do
  use ExUnit.Case, async: true

  alias Hive.Oban.Peers.Database

  defmodule SuccessfulRepo do
    def transaction(_conf, fun, opts) do
      send(self(), {:transaction_opts, opts})

      {:ok, fun.()}
    end

    def delete_all(_conf, _query) do
      send(self(), :delete_all)

      {0, nil}
    end

    def insert_all(_conf, "oban_peers", [peer_data], opts) do
      send(self(), {:insert_all, peer_data, opts})

      {1, nil}
    end

    def one(_conf, _query), do: "test-node"
  end

  defmodule ExhaustedRepo do
    def transaction(_conf, _fun, opts) do
      send(self(), {:transaction_opts, opts})

      {:error, %DBConnection.ConnectionError{message: "ssl send: closed"}}
    end
  end

  describe "handle_info/2" do
    test "becomes leader when the election transaction inserts the peer row" do
      state = state(repo: SuccessfulRepo)

      assert {:noreply, %Database{leader?: true} = updated_state} =
               Database.handle_info(:election, state)

      assert_receive {:transaction_opts, opts}
      assert opts[:on_exhausted] == :log

      assert_receive :delete_all
      assert_receive {:insert_all, peer_data, opts}

      assert peer_data.name == "Oban"
      assert peer_data.node == "test-node"
      assert opts[:conflict_target] == :name
      assert opts[:on_conflict] == :nothing

      Process.cancel_timer(updated_state.timer)
    end

    test "keeps current leadership state when the election transaction exhausts retries" do
      state = state(repo: ExhaustedRepo, leader?: true)

      assert {:noreply, %Database{leader?: true} = updated_state} =
               Database.handle_info(:election, state)

      assert_receive {:transaction_opts, opts}
      assert opts[:on_exhausted] == :log

      Process.cancel_timer(updated_state.timer)
    end
  end

  defp state(opts) do
    opts = Keyword.put_new(opts, :leader?, false)

    struct!(
      Database,
      Keyword.merge(
        [
          conf: %Oban.Config{
            engine: Oban.Engines.Basic,
            name: Oban,
            node: "test-node",
            repo: Hive.Repo
          },
          interval: :timer.minutes(1),
          repo: Keyword.fetch!(opts, :repo)
        ],
        opts
      )
    )
  end
end
