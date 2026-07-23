defmodule Hive.Agents.Tools.CreateForageItemTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Agents.Tools.CreateForageItem
  alias Hive.Audit.Activity
  alias Hive.Forage.FeatureRequest

  defp user do
    {:ok, user} =
      Accounts.upsert_from_auth(%{
        email: "agent-tool@example.com",
        provider: "test",
        provider_uid: "agent-tool"
      })

    user
  end

  test "creates a forage item for the requester in the tool context" do
    result =
      CreateForageItem.call(
        %{
          "type" => "bug_report",
          "title" => "Launch crash",
          "description" => "The app crashes when the dashboard opens."
        },
        %{assigns: %{requester_user: user()}}
      )

    assert {:ok, %{destination: "hive_item", hive_url: hive_url, title: "Launch crash"}} = result
    assert hive_url =~ "/forage/items/manual/"
    assert [%FeatureRequest{type: :bug_report, title: "Launch crash"}] = Repo.all(FeatureRequest)

    assert %Activity{interface: "worker"} =
             Repo.get_by!(Activity, action: "forage.intake.created")
  end

  test "rejects calls without a requester in the tool context" do
    assert {:error, "The Slack user is not linked to a Hive user."} =
             CreateForageItem.call(
               %{
                 "title" => "Launch crash",
                 "description" => "The app crashes when the dashboard opens."
               },
               %{assigns: %{}}
             )
  end
end
