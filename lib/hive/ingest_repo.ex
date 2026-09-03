defmodule Hive.IngestRepo do
  @moduledoc """
  Write-only repository for ClickHouse ingestion.
  """

  use Ecto.Repo,
    otp_app: :hive,
    adapter: Ecto.Adapters.ClickHouse
end
