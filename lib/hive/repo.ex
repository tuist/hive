defmodule Hive.Repo do
  use Ecto.Repo,
    otp_app: :hive,
    adapter: Ecto.Adapters.Postgres
end
