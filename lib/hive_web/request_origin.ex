defmodule HiveWeb.RequestOrigin do
  @moduledoc false

  def from_conn(_conn) do
    :boruta
    |> Application.fetch_env!(Boruta.Oauth)
    |> Keyword.fetch!(:issuer)
  end
end
