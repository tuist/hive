defmodule Hive.Errors.Fingerprint do
  @moduledoc """
  Groups events into issues. Honors an SDK-supplied `fingerprint`
  verbatim when present; otherwise computes a deterministic 64-char
  hex digest from the event's exception type, top in-app frame, and
  normalized message.
  """

  alias Hive.Errors.SentryEvent

  @spec compute(SentryEvent.t()) :: String.t()
  def compute(%SentryEvent{fingerprint_override: override}) when is_list(override) do
    override
    |> Enum.join("|")
    |> hash()
  end

  def compute(%SentryEvent{} = event) do
    type = event.exception_type || ""

    {function, location} =
      case event.top_frame do
        nil -> {"", ""}
        frame -> {frame["function"] || "", frame["module"] || frame["filename"] || ""}
      end

    message = normalize_message(event.message || event.exception_value || "")

    [type, function, location, message]
    |> Enum.join("|")
    |> hash()
  end

  defp normalize_message(binary) when is_binary(binary) do
    binary
    |> String.replace(~r/0x[0-9a-fA-F]+/, "0x*")
    |> String.replace(~r/\d+/, "N")
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 200)
    |> String.trim()
  end

  defp normalize_message(_), do: ""

  defp hash(binary) do
    :sha256
    |> :crypto.hash(binary)
    |> Base.encode16(case: :lower)
  end
end
