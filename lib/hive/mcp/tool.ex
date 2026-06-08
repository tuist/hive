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
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
