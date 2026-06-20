defmodule Hive.AuditTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts.User
  alias Hive.Audit
  alias Hive.Audit.Activity

  describe "log/2" do
    test "records actor, interface, and target attributes from a struct" do
      user = insert_user!(%{email: "auditor@example.com", name: "Auditor", role: :admin})

      {:ok, activity} =
        Audit.log("spec.created", %{
          actor: user,
          interface: "dashboard",
          target_type: "spec",
          target_id: "spec-1",
          target_label: "Some Spec",
          metadata: %{"number" => "42"}
        })

      assert activity.actor_id == user.id
      assert activity.actor_email == "auditor@example.com"
      assert activity.actor_name == "Auditor"
      assert activity.actor_role == "admin"
      assert activity.interface == "dashboard"
      assert activity.target_type == "spec"
      assert activity.target_id == "spec-1"
      assert activity.target_label == "Some Spec"
      assert activity.metadata["number"] == "42"
      assert activity.metadata["path"] == "/specs/42"
    end

    test "normalizes string-keyed attrs" do
      assert {:ok, activity} =
               Audit.log("domain.created", %{
                 "interface" => "mcp",
                 "target_type" => "domain",
                 "target_id" => "domain-id",
                 "target_label" => "Domain",
                 "metadata" => %{"source" => "test"}
               })

      assert activity.interface == "mcp"
      assert activity.metadata["source"] == "test"
      assert activity.metadata["path"] == "/domains/domain-id"

      assert Audit.serialize(activity).target.path == "/domains/domain-id"
    end

    test "validates interface against the allowed set" do
      assert {:error, changeset} = Audit.log("noop", %{interface: "telepathy"})

      assert {_, _} = changeset.errors[:interface]
    end

    test "records an agent actor with kind, name, and model in metadata" do
      {:ok, activity} =
        Audit.log("spec.created", %{
          actor: Audit.agent_actor("IssueTriageAgent", model: "anthropic:claude-opus-4-8"),
          interface: "mcp",
          target_type: "spec",
          target_id: "spec-99",
          target_label: "Triaged Spec",
          metadata: %{"number" => "99"}
        })

      assert activity.actor_kind == "agent"
      assert activity.actor_name == "IssueTriageAgent"
      assert activity.actor_email == nil
      assert activity.actor_id == nil
      assert activity.metadata["agent_model"] == "anthropic:claude-opus-4-8"

      assert Audit.serialize(activity).actor.kind == "agent"
    end

    test "defaults to system kind when no actor is supplied" do
      {:ok, activity} =
        Audit.log("grafana_alert.received", %{
          interface: "webhook",
          target_type: "grafana_alert",
          target_id: "alert-1"
        })

      assert activity.actor_kind == "system"
      assert activity.actor_id == nil
    end
  end

  describe "with_context/2 and record/3" do
    test "pulls actor and interface from process context" do
      user = insert_user!(%{email: "context@example.com", name: "Context", role: :member})

      Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
        Audit.record("spec.created", %{
          target_type: "spec",
          target_id: "spec-2",
          target_label: "Context Spec"
        })
      end)

      activity = Repo.get_by!(Activity, action: "spec.created")
      assert activity.actor_id == user.id
      assert activity.actor_email == "context@example.com"
      assert activity.actor_name == "Context"
      assert activity.actor_role == "member"
      assert activity.interface == "dashboard"
    end

    test "restores prior context when the function returns" do
      Audit.put_context(%{interface: "system"})

      Audit.with_context(%{interface: "mcp"}, fn ->
        assert Audit.current_context().interface == "mcp"
      end)

      assert Audit.current_context().interface == "system"
    end
  end

  describe "list_activities/1" do
    setup do
      {:ok, _a} =
        Audit.log("spec.updated", %{
          interface: "dashboard",
          actor_email: "alice@example.com",
          target_type: "spec",
          target_id: "spec-a"
        })

      {:ok, _b} =
        Audit.log("domain.created", %{
          interface: "mcp",
          actor_email: "bob@example.com",
          target_type: "domain",
          target_id: "domain-a"
        })

      :ok
    end

    test "filters by interface, search query, and paginates" do
      {activities, meta} = Audit.list_activities(interface: "mcp", query: "bob", page_size: 1)

      assert Enum.map(activities, & &1.action) == ["domain.created"]
      assert meta.current_page == 1
      assert meta.page_size == 1
      assert meta.total_count == 1
      refute meta.has_next_page?
    end

    test "supports exclude filters" do
      {activities, _meta} = Audit.list_activities(exclude_interface: "dashboard")

      assert Enum.map(activities, & &1.action) == ["domain.created"]
    end
  end

  describe "resource_path/3" do
    test "uses the spec number from metadata when present" do
      assert Audit.resource_path("spec", "spec-id", %{"number" => "12"}) == "/specs/12"
    end

    test "returns nil for a spec without a number (no detail route to land on)" do
      assert Audit.resource_path("spec", "spec-id", %{}) == nil
    end

    test "returns nil for unknown target types" do
      assert Audit.resource_path("unknown", "x", %{}) == nil
    end

    test "respects an explicit path override in metadata" do
      assert Audit.resource_path("spec", "spec-id", %{"path" => "/custom"}) == "/custom"
    end
  end

  defp insert_user!(attrs) do
    defaults = %{
      email: "user-#{System.unique_integer([:positive])}@example.com",
      name: "Test User",
      role: :member
    }

    %User{}
    |> User.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
