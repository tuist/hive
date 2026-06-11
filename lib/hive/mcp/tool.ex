defmodule Hive.MCP.Tool do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      @behaviour EMCP.Tool

      @impl EMCP.Tool
      def name, do: unquote(Keyword.fetch!(opts, :name))

      @impl EMCP.Tool
      def input_schema, do: unquote(Keyword.fetch!(opts, :schema))

      @impl EMCP.Tool
      def annotations do
        %{
          title: unquote(Keyword.fetch!(opts, :title)),
          readOnlyHint: unquote(Keyword.get(opts, :read_only_hint, true)),
          openWorldHint: unquote(Keyword.get(opts, :open_world_hint, false)),
          destructiveHint: unquote(Keyword.get(opts, :destructive_hint, false))
        }
      end
    end
  end

  def json_response(data) do
    EMCP.Tool.response([%{"type" => "text", "text" => JSON.encode!(data)}])
  end

  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  defp translate_error({message, opts}) do
    Enum.reduce(opts, message, &interpolate_option/2)
  end

  defp interpolate_option({key, value}, message) do
    String.replace(message, "%{#{key}}", fn _ -> stringify_option(value) end)
  end

  defp stringify_option(value) when is_binary(value), do: value
  defp stringify_option(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_option(value) when is_number(value), do: to_string(value)
  defp stringify_option(value), do: inspect(value)
end
