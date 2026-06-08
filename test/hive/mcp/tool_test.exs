defmodule Hive.MCP.ToolTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Hive.MCP.Tool

  test "formats changeset errors with interpolated options" do
    changeset =
      {%{}, %{title: :string}}
      |> Changeset.cast(%{title: "This title is too long"}, [:title])
      |> Changeset.validate_length(:title, max: 5)

    assert Tool.changeset_errors(changeset) == %{
             title: ["should be at most 5 character(s)"]
           }
  end
end
