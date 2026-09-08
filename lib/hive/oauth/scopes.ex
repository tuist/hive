defmodule Hive.OAuth.Scopes do
  @moduledoc false

  @mobile_scopes ~w(mobile.me.read mobile.forage.read mobile.specs.read mobile.drops.read)

  @umbrellas %{"mobile" => @mobile_scopes}

  @doc "Concrete granular scopes that gate `/api/v1/*`."
  @spec mobile_scopes() :: [String.t()]
  def mobile_scopes, do: @mobile_scopes

  @doc "Umbrella scope names that expand to a concrete set."
  @spec umbrellas() :: %{String.t() => [String.t()]}
  def umbrellas, do: @umbrellas

  @doc """
  Rewrites a space-separated scope string, replacing each umbrella token with
  its concrete expansion. Preserves the order of first occurrence for every
  resulting scope and deduplicates.

  Nil and empty input are returned unchanged so a caller can pass the incoming
  parameter straight through.
  """
  @spec expand(String.t() | nil) :: String.t() | nil
  def expand(nil), do: nil

  def expand(scope) when is_binary(scope) do
    scope
    |> String.split(" ", trim: true)
    |> Enum.flat_map(&Map.get(@umbrellas, &1, [&1]))
    |> Enum.uniq()
    |> Enum.join(" ")
  end
end
