defmodule Hive.GitHub.IssueRefsTest do
  use ExUnit.Case, async: true

  alias Hive.GitHub.IssueRefs

  describe "extract/2" do
    test "captures issue and pull-request URLs from arbitrary text" do
      body = """
      See https://github.com/tuist/hive/pull/47 for the unified items work
      and https://github.com/tuist/noora/issues/118 for the dropdown polish.
      """

      assert IssueRefs.extract(body) == [
               %{owner: "tuist", name: "hive", number: 47},
               %{owner: "tuist", name: "noora", number: 118}
             ]
    end

    test "captures the cross-repo shorthand" do
      body = "Backports tuist/tuist#9999 into hive."

      assert IssueRefs.extract(body) == [
               %{owner: "tuist", name: "tuist", number: 9999}
             ]
    end

    test "resolves bare #N references with the default repo" do
      body = "Fixes #42 and closes #43."

      assert IssueRefs.extract(body, default_repo: {"tuist", "hive"}) == [
               %{owner: "tuist", name: "hive", number: 42},
               %{owner: "tuist", name: "hive", number: 43}
             ]
    end

    test "drops bare #N when no default repo is provided" do
      assert IssueRefs.extract("Fixes #42.") == []
    end

    test "deduplicates references" do
      body = """
      tuist/hive#10
      https://github.com/tuist/hive/issues/10
      #10
      """

      assert [%{owner: "tuist", name: "hive", number: 10}] =
               IssueRefs.extract(body, default_repo: {"tuist", "hive"})
    end

    test "honours the :limit option" do
      body = Enum.map_join(1..20, "\n", &"tuist/hive##{&1}")

      assert IssueRefs.extract(body, limit: 3) |> length() == 3
    end

    test "returns [] for nil or unsupported input" do
      assert IssueRefs.extract(nil) == []
      assert IssueRefs.extract(:not_a_string) == []
    end
  end
end
