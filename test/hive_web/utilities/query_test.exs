defmodule HiveWeb.Utilities.QueryTest do
  use ExUnit.Case, async: true

  alias HiveWeb.Utilities.Query

  describe "csv_list/1" do
    test "parses a comma-separated query parameter" do
      assert Query.csv_list(" a, b ,,a,c ") == ["a", "b", "c"]
    end

    test "returns an empty list for absent or invalid values" do
      assert Query.csv_list(nil) == []
      assert Query.csv_list(["a"]) == []
    end
  end
end
