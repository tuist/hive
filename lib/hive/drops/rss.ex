defmodule Hive.Drops.Rss do
  @moduledoc """
  Minimal Atom 1.0 / RSS 2.0 parser used by `Hive.Drops.RssSyncer`.

  Returns a list of entries with normalized fields:

      %{
        external_id: String.t(),
        title: String.t(),
        body: String.t() | nil,
        url: String.t() | nil,
        published_at: DateTime.t() | nil
      }

  The parser is intentionally tolerant: missing fields fall back to a
  deterministic guid derived from the entry payload so a feed without
  explicit `<guid>` or `<id>` tags still upserts cleanly.
  """

  @behaviour Saxy.Handler

  def parse(xml) when is_binary(xml) do
    case Saxy.parse_string(xml, __MODULE__, initial_state()) do
      {:ok, state} ->
        {:ok, finalize(state)}

      {:error, %Saxy.ParseError{} = error} ->
        {:error, {:parse_error, Saxy.ParseError.message(error)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  def handle_event(:end_document, _data, state), do: {:ok, state}

  def handle_event(:start_element, {name, attrs}, state) do
    local = local_name(name)
    state = push_path(state, local)
    state = maybe_start_entry(state, local)
    state = maybe_capture_link_attr(state, local, attrs)
    {:ok, %{state | buffer: ""}}
  end

  def handle_event(:end_element, name, state) do
    local = local_name(name)
    state = capture_field(state, local)
    state = maybe_finish_entry(state, local)
    {:ok, pop_path(state)}
  end

  def handle_event(:characters, chars, state) do
    {:ok, %{state | buffer: state.buffer <> chars}}
  end

  def handle_event(:cdata, chars, state) do
    {:ok, %{state | buffer: state.buffer <> chars}}
  end

  def handle_event(_event, _data, state), do: {:ok, state}

  defp initial_state do
    %{
      path: [],
      buffer: "",
      entry: nil,
      entries: []
    }
  end

  defp finalize(%{entries: entries}) do
    entries
    |> Enum.reverse()
    |> Enum.map(&normalize_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp local_name(name) when is_binary(name) do
    name
    |> String.split(":", parts: 2)
    |> List.last()
    |> String.downcase()
  end

  defp push_path(state, name), do: %{state | path: [name | state.path]}

  defp pop_path(%{path: []} = state), do: state
  defp pop_path(%{path: [_top | rest]} = state), do: %{state | path: rest}

  defp maybe_start_entry(state, local) when local in ["item", "entry"] do
    %{state | entry: %{}}
  end

  defp maybe_start_entry(state, _local), do: state

  defp maybe_finish_entry(%{entry: nil} = state, _local), do: state

  defp maybe_finish_entry(%{entry: entry} = state, local) when local in ["item", "entry"] do
    %{state | entry: nil, entries: [entry | state.entries]}
  end

  defp maybe_finish_entry(state, _local), do: state

  defp capture_field(%{entry: nil} = state, _local), do: state

  defp capture_field(state, local) do
    buffer = String.trim(state.buffer)

    cond do
      buffer == "" and local not in ["link"] ->
        state

      local in ["title"] ->
        put_field(state, :title, buffer)

      local in ["id", "guid"] ->
        put_field(state, :external_id, buffer)

      local in ["link"] ->
        put_field(state, :url, buffer)

      local in ["pubdate", "published", "updated"] ->
        put_field(state, :published_at, buffer)

      local in ["description", "summary", "content", "encoded"] ->
        put_field(state, :body, buffer)

      true ->
        state
    end
  end

  defp maybe_capture_link_attr(%{entry: nil} = state, _local, _attrs), do: state

  defp maybe_capture_link_attr(state, "link", attrs) when is_list(attrs) do
    case attr_value(attrs, "href") do
      href when is_binary(href) and href != "" ->
        put_url_field(state, href, attr_value(attrs, "rel"))

      _other ->
        state
    end
  end

  defp maybe_capture_link_attr(state, _local, _attrs), do: state

  defp put_field(%{entry: entry} = state, key, value) when is_binary(value) and value != "" do
    %{state | entry: Map.put_new(entry, key, value)}
  end

  defp put_field(state, _key, _value), do: state

  defp put_url_field(%{entry: entry} = state, href, rel) do
    rel = normalize_rel(rel)
    preferred? = preferred_link_rel?(rel)
    current_rel = Map.get(entry, :url_rel)

    cond do
      is_nil(Map.get(entry, :url)) ->
        %{state | entry: entry |> Map.put(:url, href) |> Map.put(:url_rel, rel)}

      preferred? and not preferred_link_rel?(current_rel) ->
        %{state | entry: entry |> Map.put(:url, href) |> Map.put(:url_rel, rel)}

      true ->
        state
    end
  end

  defp attr_value(attrs, name) do
    attrs
    |> Enum.find_value(fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  defp normalize_rel(nil), do: ""

  defp normalize_rel(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp preferred_link_rel?(rel), do: rel in ["", "alternate"]

  defp normalize_entry(entry) when map_size(entry) == 0, do: nil

  defp normalize_entry(entry) do
    title = Map.get(entry, :title, "Untitled")
    url = Map.get(entry, :url)
    body = Map.get(entry, :body)
    published_at = parse_timestamp(Map.get(entry, :published_at))

    external_id =
      Map.get(entry, :external_id) ||
        url ||
        derive_guid(title, body, published_at)

    %{
      external_id: truncate(external_id, 500),
      title: truncate(strip_tags(title), 500),
      body: body,
      url: url,
      published_at: published_at
    }
  end

  defp derive_guid(title, body, published_at) do
    payload =
      [title, body, format_for_guid(published_at)]
      |> Enum.map_join("|", &to_string/1)

    :sha256
    |> :crypto.hash(payload)
    |> Base.encode16(case: :lower)
  end

  defp format_for_guid(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_for_guid(_other), do: ""

  defp parse_timestamp(nil), do: nil
  defp parse_timestamp(""), do: nil

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> parse_rfc1123(value)
    end
  end

  defp parse_rfc1123(value) do
    try do
      case :httpd_util.convert_request_date(String.to_charlist(value)) do
        {{year, month, day}, {hour, minute, second}} ->
          case NaiveDateTime.new(year, month, day, hour, minute, second) do
            {:ok, naive} ->
              naive |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

            _ ->
              nil
          end

        _ ->
          nil
      end
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp strip_tags(value) when is_binary(value) do
    value
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp strip_tags(value), do: value

  defp truncate(value, max) when is_binary(value) and byte_size(value) > max,
    do: String.slice(value, 0, max)

  defp truncate(value, _max), do: value
end
