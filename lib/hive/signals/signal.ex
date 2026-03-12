defmodule Hive.Signals.Signal do
  use Hive.Schema
  import Ecto.Changeset

  @statuses [:new, :in_flight, :needs_review, :resolved, :ignored]
  def statuses, do: @statuses

  schema "signals" do
    field :title, :string
    field :body, :string
    field :source, :string
    field :status, Ecto.Enum, values: @statuses, default: :new
    field :source_url, :string
    field :source_author, :string
    field :source_channel, :string
    field :source_timestamp, :utc_datetime

    has_many :messages, Hive.Signals.SignalMessage

    timestamps()
  end

  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [
      :title,
      :body,
      :source,
      :status,
      :source_url,
      :source_author,
      :source_channel,
      :source_timestamp
    ])
    |> validate_required([:title, :source])
  end
end
