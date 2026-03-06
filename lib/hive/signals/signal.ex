defmodule Hive.Signals.Signal do
  use Hive.Schema
  import Ecto.Changeset

  schema "signals" do
    field :title, :string
    field :body, :string
    field :source, :string
    field :source_url, :string
    field :source_author, :string
    field :source_channel, :string
    field :source_timestamp, :utc_datetime

    timestamps()
  end

  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [
      :title,
      :body,
      :source,
      :source_url,
      :source_author,
      :source_channel,
      :source_timestamp
    ])
    |> validate_required([:title, :source])
  end
end
