defmodule Hive.Signals.SignalMessage do
  use Hive.Schema
  import Ecto.Changeset

  schema "signal_messages" do
    field :author, :string
    field :body, :string
    field :source_url, :string
    field :source_timestamp, :utc_datetime

    belongs_to :signal, Hive.Signals.Signal

    timestamps()
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:author, :body, :source_url, :source_timestamp, :signal_id])
    |> validate_required([:body, :signal_id])
  end
end
