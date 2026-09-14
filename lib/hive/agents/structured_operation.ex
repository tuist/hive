defmodule Hive.Agents.StructuredOperation do
  @moduledoc "Single-response execution of operations that do not use tools."

  def run(agent, name, args, opts) do
    with {:ok, operation} <- fetch_operation(agent, name),
         :ok <- without_tools(agent),
         {:ok, input} <- validate(operation.input_schema, normalize(args), :invalid_input),
         {model, request_opts} = Keyword.pop!(opts, :model),
         {:ok, response} <-
           ReqLLM.generate_object(
             model,
             [
               ReqLLM.Context.system(agent.system_prompt() <> "\n\n" <> operation.instructions),
               ReqLLM.Context.user(JSON.encode!(input))
             ],
             operation.output_schema,
             request_opts
           ),
         {:ok, output} <-
           validate(operation.output_schema, ReqLLM.Response.object(response), :invalid_output) do
      {:ok, atomize_properties(output, operation.output_schema)}
    end
  end

  defp fetch_operation(agent, name) do
    case agent.__operation__(name) do
      {:ok, operation} -> {:ok, operation}
      :error -> {:error, {:unknown_operation, name}}
    end
  end

  defp without_tools(agent) do
    if agent.tools() == [], do: :ok, else: {:error, :operation_requires_tools}
  end

  defp validate(schema, value, reason) do
    with {:ok, root} <- JSV.build(schema),
         {:ok, value} <- JSV.validate(value, root) do
      {:ok, value}
    else
      {:error, error} -> {:error, {reason, error}}
    end
  end

  defp normalize(value), do: value |> JSON.encode!() |> JSON.decode!()

  defp atomize_properties(output, schema) do
    properties = Map.get(schema, :properties, %{})
    names = Map.new(properties, fn {key, _} -> {to_string(key), key} end)
    Map.new(output, fn {key, value} -> {Map.get(names, key, key), value} end)
  end
end
