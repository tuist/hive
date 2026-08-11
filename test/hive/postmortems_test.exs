defmodule Hive.PostmortemsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Postmortems
  alias Hive.Postmortems.ActionItem
  alias Hive.Postmortems.Embedding
  alias Hive.Repo

  defp user(email \\ "postmortems@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  test "publishes a Markdown postmortem and uses its first line as the title" do
    assert {:ok, postmortem} =
             Postmortems.publish_postmortem(
               %{"body" => "# Database incident\n\nThe database was unavailable."},
               user()
             )

    assert Postmortems.title(postmortem) == "Database incident"
    assert [listed] = Postmortems.list_postmortems()
    assert listed.id == postmortem.id
    assert listed.number == postmortem.number
  end

  test "assigns consecutive public numbers" do
    {:ok, first} =
      Postmortems.publish_postmortem(
        %{"body" => "# First incident\n\nThe first incident."},
        user()
      )

    {:ok, second} =
      Postmortems.publish_postmortem(
        %{"body" => "# Second incident\n\nThe second incident."},
        user()
      )

    assert second.number == first.number + 1
  end

  test "persists an embedding once for unchanged content and retrieves it semantically" do
    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Delivery delay\n\nA worker backlog delayed customer notifications."},
        user()
      )

    content_hash = :crypto.hash(:sha256, postmortem.body) |> Base.encode16(case: :lower)

    embed = fn _text ->
      send(self(), :embedded)
      {:ok, [0.8, 0.2]}
    end

    assert {:ok, %Embedding{status: :indexed}} =
             Postmortems.index_postmortem(postmortem.id, content_hash, embed: embed)

    assert_received :embedded

    assert {:ok, %Embedding{status: :indexed}} =
             Postmortems.index_postmortem(postmortem.id, content_hash, embed: embed)

    refute_received :embedded

    assert %Embedding{embedding: [0.8, 0.2]} =
             Repo.get_by(Embedding, postmortem_id: postmortem.id)

    assert {:ok, [%{postmortem: result, score: score}]} =
             Postmortems.semantic_search("notification delays",
               embed: fn _ -> {:ok, [0.8, 0.2]} end
             )

    assert result.id == postmortem.id
    assert_in_delta score, 1.0, 0.000_001
  end

  test "does not allow anonymous publishing" do
    assert Postmortems.publish_postmortem(%{"body" => "# Incident\n\nDetails."}, nil) ==
             {:error, :unauthorized}
  end

  test "creates, updates, completes, reopens, and deletes action items" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Registry delay\n\nPackage resolution was delayed."},
        owner
      )

    assert {:ok, %ActionItem{} = action_item} =
             Postmortems.create_action_item(
               postmortem,
               %{"title" => "Add a registry latency alert"},
               owner
             )

    assert {:ok, action_item} =
             Postmortems.update_action_item(
               postmortem,
               action_item,
               %{"title" => "Add a registry latency alert and runbook"},
               owner
             )

    assert {:ok, %{completed_at: completed_at} = action_item} =
             Postmortems.toggle_action_item(postmortem, action_item, owner)

    assert completed_at

    assert {:ok, %{completed_at: nil} = action_item} =
             Postmortems.toggle_action_item(postmortem, action_item, owner)

    assert {:ok, _action_item} = Postmortems.delete_action_item(postmortem, action_item, owner)
  end

  test "uses the first level-one Markdown heading as the title" do
    assert Postmortems.title(
             "Introduction\n\n## Not the title\n\n# Registry incident\n\nDetails."
           ) ==
             "Registry incident"
  end
end
