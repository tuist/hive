defmodule Hive.OpendataVectorTest do
  use ExUnit.Case, async: true

  alias Hive.OpendataVector

  describe "base_url/1" do
    test "returns disabled when no opendata-vector URL is configured" do
      assert OpendataVector.base_url([]) == :disabled
      assert OpendataVector.base_url(base_url: " ") == :disabled
    end

    test "returns the trimmed opendata-vector URL when configured" do
      assert OpendataVector.base_url(base_url: " http://hive-vector:8080 ") ==
               {:ok, "http://hive-vector:8080"}
    end
  end
end
