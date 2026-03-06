defmodule Hive.Signals do
  alias Hive.Repo
  alias Hive.Signals.Signal
  alias Hive.Signals.SignalMessage

  import Ecto.Query

  def list_signals(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Signal
    |> order_by([s], desc: s.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_signal(id) do
    Signal
    |> Repo.get(id)
    |> Repo.preload(
      messages: from(m in SignalMessage, order_by: [asc: m.source_timestamp, asc: m.inserted_at])
    )
  end

  def get_signal_by_source_url(source_url) do
    Signal
    |> where([s], s.source_url == ^source_url)
    |> Repo.one()
  end

  def create_signal(attrs) do
    %Signal{}
    |> Signal.changeset(attrs)
    |> Repo.insert()
  end

  def add_signal_message(%Signal{} = signal, attrs) do
    attrs = Map.put(attrs, :signal_id, signal.id)

    %SignalMessage{}
    |> SignalMessage.changeset(attrs)
    |> Repo.insert()
  end
end
