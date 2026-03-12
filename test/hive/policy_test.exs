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

  describe "signal:write" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:signal_write, %{}, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:signal_write, subject, %{})
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

  describe "integration:write" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:integration_write, %{}, %{})
    end

    test "denies when current_user is nil" do
      subject = %{current_user: nil}
      assert {:error, :unauthorized} = Policy.authorize(:integration_write, subject, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:integration_write, subject, %{})
    end
  end

  describe "integration:read" do
    test "denies unauthenticated users" do
      assert {:error, :unauthorized} = Policy.authorize(:integration_read, %{}, %{})
    end

    test "allows authenticated users" do
      subject = %{current_user: %{id: "user-123"}}
      assert :ok = Policy.authorize(:integration_read, subject, %{})
    end
  end
end
