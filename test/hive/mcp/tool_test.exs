defmodule Hive.MCP.ToolTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Hive.MCP.Tool

  defmodule StrictTool do
    @moduledoc false

    use Hive.MCP.Tool,
      name: "strict_tool",
      title: "Strict Tool",
      schema: %{"type" => "object", "properties" => %{}},
      output_schema: Hive.MCP.Tool.result_schema(%{"answer" => %{"type" => "string"}}, ["answer"])

    @impl EMCP.Tool
    def description, do: "Exercises output schema validation."

    @impl EMCP.Tool
    def call(_conn, _args), do: json_response(%{answer: "42"})
  end

  describe "json_response/2" do
    test "returns the text content and the structured content side by side" do
      assert StrictTool.call(%{}, %{}) == %{
               "content" => [%{"type" => "text", "text" => ~s({"answer":"42"})}],
               "structuredContent" => %{"answer" => "42"}
             }
    end

    test "serializes an error payload through the schema's error branch" do
      assert %{"structuredContent" => %{"error" => "not_found"}} =
               StrictTool.json_response(%{error: "not_found"})
    end

    test "raises when the payload does not match the declared output schema" do
      assert_raise RuntimeError, ~r/strict_tool returned invalid structured content/, fn ->
        StrictTool.json_response(%{answer: 42})
      end
    end

    test "raises when the payload is not a map" do
      assert_raise ArgumentError, ~r/strict_tool must return a map as structured content/, fn ->
        Tool.json_response([1, 2, 3], StrictTool)
      end
    end
  end

  describe "output schemas" do
    test "descriptor/1 attaches the output schema to the tools/list entry" do
      descriptor = Tool.descriptor(StrictTool)

      assert descriptor["name"] == "strict_tool"
      assert descriptor["outputSchema"] == StrictTool.output_schema()
    end

    test "a tool that declares a non-object output schema fails to compile" do
      assert_raise ArgumentError, ~r/must provide an object output schema/, fn ->
        Code.eval_string("""
        defmodule Hive.MCP.ToolTest.ArrayOutputSchemaTool do
          use Hive.MCP.Tool,
            name: "array_output_schema_tool",
            title: "Array Output Schema Tool",
            schema: %{"type" => "object"},
            output_schema: %{"type" => "array"}

          def description, do: "Invalid."
          def call(_conn, _args), do: json_response(%{})
        end
        """)
      end
    end

    test "result_schema/2 accepts either the success payload or an error object" do
      resolved =
        %{"project" => %{"type" => "object"}}
        |> Tool.result_schema(["project"])
        |> ExJsonSchema.Schema.resolve()

      assert :ok = ExJsonSchema.Validator.validate(resolved, %{"project" => %{}})
      assert :ok = ExJsonSchema.Validator.validate(resolved, %{"error" => "not_found"})

      assert :ok =
               ExJsonSchema.Validator.validate(resolved, %{
                 "error" => "invalid",
                 "details" => %{"name" => ["can't be blank"]}
               })

      assert {:error, _errors} = ExJsonSchema.Validator.validate(resolved, %{})

      assert {:error, _errors} =
               ExJsonSchema.Validator.validate(resolved, %{"project" => %{}, "error" => "nope"})
    end

    test "result_schema/3 lets a failure carry its own context" do
      resolved =
        %{"spec" => %{"type" => "object"}}
        |> Tool.result_schema(["spec"], %{"current_revision" => %{"type" => "integer"}})
        |> ExJsonSchema.Schema.resolve()

      assert :ok =
               ExJsonSchema.Validator.validate(resolved, %{
                 "error" => "stale_revision",
                 "current_revision" => 3
               })

      assert :ok = ExJsonSchema.Validator.validate(resolved, %{"spec" => %{}})

      assert {:error, _errors} =
               ExJsonSchema.Validator.validate(resolved, %{
                 "error" => "stale_revision",
                 "current_revision" => "3"
               })
    end
  end

  test "formats changeset errors with interpolated options" do
    changeset =
      {%{}, %{title: :string}}
      |> Changeset.cast(%{title: "This title is too long"}, [:title])
      |> Changeset.validate_length(:title, max: 5)

    assert Tool.changeset_errors(changeset) == %{
             title: ["should be at most 5 character(s)"]
           }
  end

  test "formats Ecto.Enum cast errors without crashing on parameterized type opts" do
    types = %{
      status: Ecto.ParameterizedType.init(Ecto.Enum, values: [:draft, :proposed, :approved])
    }

    changeset = Changeset.cast({%{}, types}, %{status: "bogus"}, [:status])

    assert Tool.changeset_errors(changeset) == %{status: ["is invalid"]}
  end
end
