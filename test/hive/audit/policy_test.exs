defmodule Hive.Audit.PolicyTest do
  use ExUnit.Case, async: true

  alias Hive.Accounts.User
  alias Hive.Audit.Policy

  test "admin users can read the audit trail" do
    assert Policy.authorize?(:audit_activity_read, %User{role: :admin}, nil)
  end

  test "member users cannot read the audit trail" do
    refute Policy.authorize?(:audit_activity_read, %User{role: :member}, nil)
  end

  test "anonymous visitors cannot read the audit trail" do
    refute Policy.authorize?(:audit_activity_read, nil, nil)
  end
end
