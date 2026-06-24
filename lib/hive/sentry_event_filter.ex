defmodule Hive.SentryEventFilter do
  @moduledoc """
  Drops expected web noise before events are sent to Sentry.
  """

  alias Phoenix.Router.NoRouteError

  @ignored_exceptions [
    Bandit.HTTPError,
    Bandit.TransportError,
    NoRouteError
  ]

  @ignored_exception_types Enum.map(@ignored_exceptions, &inspect/1)

  def before_send(%Sentry.Event{original_exception: exception, source: source} = event)
      when is_exception(exception) do
    if ignored_connection_retry?(event) or
         exception.__struct__ in @ignored_exceptions or
         Sentry.DefaultEventFilter.exclude_exception?(exception, source) do
      false
    else
      event
    end
  end

  def before_send(%Sentry.Event{exception: exceptions} = event) when is_list(exceptions) do
    if Enum.any?(exceptions, &ignored_exception?/1) do
      false
    else
      event
    end
  end

  def before_send(event), do: event

  defp ignored_connection_retry?(%Sentry.Event{
         original_exception: %DBConnection.ConnectionError{message: message},
         source: :logger
       })
       when is_binary(message) do
    String.starts_with?(message, "tcp connect ") and
      String.contains?(message, [":econnrefused", ":eperm"])
  end

  defp ignored_connection_retry?(_event), do: false

  defp ignored_exception?(%{type: type}) when is_binary(type),
    do: type in @ignored_exception_types

  defp ignored_exception?(_), do: false
end
