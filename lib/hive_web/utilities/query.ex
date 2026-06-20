defmodule HiveWeb.Utilities.Query do
  @moduledoc """
  Utilities for working with URI query parameters.

  Mirrors the small surface used by paginated/filtered LiveView pages so
  templates can compose patch URLs like
  `Query.put(@uri.query, "page", page)`.
  """

  @doc """
  Updates a query parameter with a new value.

  ## Examples

      iex> HiveWeb.Utilities.Query.put("foo=bar", "baz", "qux")
      "baz=qux&foo=bar"

      iex> HiveWeb.Utilities.Query.put("foo=bar&baz=old", "baz", "new")
      "baz=new&foo=bar"

      iex> HiveWeb.Utilities.Query.put(nil, "page", 2)
      "page=2"
  """
  def put(query, key, value) when is_binary(query) or is_nil(query) do
    (query || "")
    |> URI.decode_query()
    |> Map.put(key, to_string(value))
    |> URI.encode_query()
  end

  def put(query, key, value) when is_map(query) do
    query
    |> Map.put(key, to_string(value))
    |> URI.encode_query()
  end

  @doc """
  Puts a query parameter when the value is present. Nil and blank string
  values are ignored.
  """
  def put_present(params, _key, nil) when is_map(params), do: params
  def put_present(params, _key, "") when is_map(params), do: params

  def put_present(params, key, value) when is_map(params) do
    Map.put(params, key, value)
  end

  @doc """
  Drops a query parameter.

  ## Examples

      iex> HiveWeb.Utilities.Query.drop("foo=bar&baz=qux", "baz")
      "foo=bar"

      iex> HiveWeb.Utilities.Query.drop("foo=bar", "missing")
      "foo=bar"
  """
  def drop(query, key) when is_binary(query) or is_nil(query) do
    (query || "")
    |> URI.decode_query()
    |> Map.delete(key)
    |> URI.encode_query()
  end

  def drop(query, key) when is_map(query) do
    query
    |> Map.delete(key)
    |> URI.encode_query()
  end

  @doc """
  Extracts decoded query parameters from a URI string.
  """
  def query_params(uri) when is_binary(uri) do
    case URI.parse(uri).query do
      nil -> %{}
      query -> URI.decode_query(query)
    end
  end

  def query_params(nil), do: %{}

  @doc """
  Parses a positive page number, defaulting invalid values to 1.
  """
  def parse_page(nil), do: 1
  def parse_page(page) when is_integer(page) and page >= 1, do: page

  def parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {number, ""} when number >= 1 -> number
      _other -> 1
    end
  end

  def parse_page(_page), do: 1

  @doc "Normalizes blank strings to nil and trims present strings."
  def present_string(nil), do: nil

  def present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def present_string(_value), do: nil

  @doc """
  Parses a comma-separated query parameter into a de-duplicated list of
  trimmed values.
  """
  def csv_list(nil), do: []

  def csv_list(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def csv_list(_value), do: []
end
