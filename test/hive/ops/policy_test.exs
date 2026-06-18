defmodule Hive.Ops.PolicyTest do
  use ExUnit.Case, async: true

  alias Hive.Accounts.User
  alias Hive.Ops.Policy

  test "admin users can manage Slack workspaces" do
    assert Policy.authorize?(:slack_workspace_manage, %User{role: :admin}, nil)
  end

  test "member users cannot manage Slack workspaces" do
    refute Policy.authorize?(:slack_workspace_manage, %User{role: :member}, nil)
  end

  test "anonymous visitors cannot manage Slack workspaces" do
    refute Policy.authorize?(:slack_workspace_manage, nil, nil)
  end
end
