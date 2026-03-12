defmodule Hive.PolicyTest do
  use Hive.DataCase, async: true

  alias Hive.Policy

  describe "signal:read" do
    test "allows unauthenticated users" do
      assert :ok = Policy.authorize(:signal_read, %{}, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:signal_read, subject, %{})
    end
  end

  describe "swarm:read" do
    test "allows unauthenticated users" do
      assert :ok = Policy.authorize(:swarm_read, %{}, %{})
    end
  end

  describe "instance:read" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:instance_read, %{}, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:instance_read, subject, %{})
    end
  end

  describe "slack_integration:write" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:slack_integration_write, %{}, %{})
    end

    test "denies when current_user is nil" do
      subject = %{current_user: nil}
      assert {:error, :unauthorized} = Policy.authorize(:slack_integration_write, subject, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:slack_integration_write, subject, %{})
    end
  end

  describe "github_app:write" do
    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:github_app_write, subject, %{})
    end
  end
end
