defmodule Hive.Repo do
  use Ecto.Repo,
    otp_app: :hive,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def default_options(_operation) do
    [prepare: :unnamed]
  end
end
