defmodule Hive.MCP.Tool do
  @moduledoc false

  require Logger

  @strict_output_schemas Mix.env() != :prod

  defmacro __using__(opts) do
    quote do
      @behaviour EMCP.Tool

      @mcp_tool_name Keyword.fetch!(unquote(opts), :name)
      @mcp_tool_output_schema Hive.MCP.Tool.validate_output_schema!(
                                @mcp_tool_name,
                                Keyword.fetch!(unquote(opts), :output_schema)
                              )
      @mcp_tool_resolved_output_schema ExJsonSchema.Schema.resolve(@mcp_tool_output_schema)

      @impl EMCP.Tool
      def name, do: @mcp_tool_name

      @impl EMCP.Tool
      def input_schema, do: unquote(Keyword.fetch!(opts, :schema))

      def output_schema, do: @mcp_tool_output_schema

      def resolved_output_schema, do: @mcp_tool_resolved_output_schema

      @impl EMCP.Tool
      def annotations do
        %{
          title: unquote(Keyword.fetch!(opts, :title)),
          readOnlyHint: unquote(Keyword.get(opts, :read_only_hint, true)),
          openWorldHint: unquote(Keyword.get(opts, :open_world_hint, false)),
          destructiveHint: unquote(Keyword.get(opts, :destructive_hint, false))
        }
      end

      def json_response(data), do: Hive.MCP.Tool.json_response(data, __MODULE__)
    end
  end

  @doc """
  Serializes a tool payload as both the text content every client understands and the
  `structuredContent` that conforms to the tool's declared output schema.
  """
  def json_response(data, module) when is_map(data) do
    encoded = JSON.encode!(data)
    structured_content = JSON.decode!(encoded)

    validate_structured_content(module, structured_content)

    [%{"type" => "text", "text" => encoded}]
    |> EMCP.Tool.response()
    |> Map.put("structuredContent", structured_content)
  end

  def json_response(data, module) do
    raise ArgumentError,
          "MCP tool #{module.name()} must return a map as structured content, got: #{inspect(data)}"
  end

  @doc """
  Asserts at compile time that a tool declares an object output schema. A tool that
  violates this would otherwise only fail once a client requested `tools/list`, taking
  down tool discovery for every other tool along with it.
  """
  def validate_output_schema!(name, schema) do
    if not is_map(schema) or
         (schema["type"] not in ["object", :object] and schema[:type] not in ["object", :object]) do
      raise ArgumentError, "MCP tool #{name} must provide an object output schema"
    end

    schema
  end

  @doc """
  The `tools/list` entry for a tool, with its output schema attached.
  """
  def descriptor(module) do
    module
    |> EMCP.Tool.to_map()
    |> Map.put("outputSchema", module.output_schema())
  end

  @doc """
  Every Hive tool answers either with its success payload or with an error object, so
  each output schema is a union of the two. `properties` describes the success payload
  and `required` lists the keys it always carries. `error_properties` extends the error
  object for tools whose failures carry more than the error name, such as the stale
  revision a write lost to.
  """
  def result_schema(properties, required, error_properties \\ %{}) do
    %{
      "type" => "object",
      "oneOf" => [
        %{
          "type" => "object",
          "properties" => properties,
          "required" => required,
          "additionalProperties" => false
        },
        error_schema(error_properties)
      ]
    }
  end

  @doc """
  The error object a tool returns instead of its success payload. `error` names the
  failure; `details`, `labels`, and any tool-specific keys carry its context. Only
  `error` distinguishes this branch from a success payload, so it is the one key
  every failure must set.
  """
  def error_schema(extra_properties \\ %{}) do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(
          %{
            "error" => %{"type" => "string"},
            "details" => %{"type" => "object"},
            "labels" => %{"type" => "array", "items" => %{"type" => "string"}}
          },
          extra_properties
        ),
      "required" => ["error"],
      "additionalProperties" => false
    }
  end

  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  # Schema drift is a bug in the tool's declared output schema, not in the caller's
  # request. Raise where a test or a developer sees it immediately, but never turn a
  # successful query into a 500 for a client that could have used the response.
  # Logged at :error so the Sentry handler, which only captures :error, reports it.
  defp validate_structured_content(module, structured_content) do
    case ExJsonSchema.Validator.validate(module.resolved_output_schema(), structured_content) do
      :ok ->
        :ok

      {:error, errors} ->
        message =
          "MCP tool #{module.name()} returned invalid structured content: #{inspect(errors)}"

        if @strict_output_schemas do
          raise message
        else
          Logger.error(message)
          :ok
        end
    end
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
