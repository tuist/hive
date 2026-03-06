defmodule Hive.PolicyTest do
  use Hive.DataCase, async: true

  alias Hive.Policy

  describe "dashboard:read" do
    test "allows unauthenticated users" do
      assert :ok = Policy.authorize(:dashboard_read, %{}, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:dashboard_read, subject, %{})
    end
  end

  describe "dashboard:write" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:dashboard_write, %{}, %{})
    end

    test "denies when current_user is nil" do
      subject = %{current_user: nil}
      assert {:error, :unauthorized} = Policy.authorize(:dashboard_write, subject, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:dashboard_write, subject, %{})
    end
  end
end
