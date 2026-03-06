defmodule Hive.Signals do
  alias Hive.Repo
  alias Hive.Signals.Signal

  import Ecto.Query

  def list_signals(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Signal
    |> order_by([s], desc: s.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def create_signal(attrs) do
    %Signal{}
    |> Signal.changeset(attrs)
    |> Repo.insert()
  end
end
