defmodule Hive.PostmortemsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Audit.Activity
  alias Hive.Domains
  alias Hive.Postmortems
  alias Hive.Postmortems.ActionItem
  alias Hive.Postmortems.Embedding
  alias Hive.Projects
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

  test "assigns increasing public numbers" do
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

    assert second.number > first.number
  end

  test "persists an embedding once for unchanged content and retrieves it semantically" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Delivery delay\n\nA worker backlog delayed customer notifications."},
        owner
      )

    content_hash = :crypto.hash(:sha256, postmortem.body) |> Base.encode16(case: :lower)

    embed = fn _text ->
      send(self(), :embedded)
      {:ok, [0.8, 0.2]}
    end

    assert {:ok, %Embedding{status: :indexed}} =
             Postmortems.index_postmortem(postmortem.id, content_hash, embed: embed)

    assert_received :embedded

    assert {:ok, _postmortem} =
             Postmortems.update_postmortem(postmortem, %{"body" => postmortem.body}, owner)

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

  test "does not let an older embedding overwrite changed content" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Initial incident\n\nThe initial account has enough detail."},
        owner
      )

    initial_hash = content_hash(postmortem.body)
    updated_body = "# Updated incident\n\nThe corrected account has enough detail."

    embed = fn _body ->
      assert {:ok, _postmortem} =
               Postmortems.update_postmortem(postmortem, %{"body" => updated_body}, owner)

      {:ok, [0.8, 0.2]}
    end

    assert {:ok, :stale} =
             Postmortems.index_postmortem(postmortem.id, initial_hash, embed: embed)

    assert %Embedding{
             content_hash: updated_hash,
             status: :pending,
             embedding: nil,
             indexed_at: nil
           } = Repo.get_by!(Embedding, postmortem_id: postmortem.id)

    assert updated_hash == content_hash(updated_body)
  end

  test "caps the text sent for indexing so long postmortems stay indexable" do
    owner = user()
    body = "# Long incident\n\n" <> String.duplicate("The account keeps going. ", 2_000)

    {:ok, postmortem} = Postmortems.publish_postmortem(%{"body" => body}, owner)

    embed = fn text ->
      send(self(), {:embedded, String.length(text)})
      {:ok, [0.8, 0.2]}
    end

    assert {:ok, %Embedding{status: :indexed}} =
             Postmortems.index_postmortem(postmortem.id, content_hash(postmortem.body),
               embed: embed
             )

    assert_received {:embedded, length}
    assert length < String.length(body)
  end

  test "semantic search applies postmortem visibility" do
    owner = user()

    {:ok, public_postmortem} =
      Postmortems.publish_postmortem(
        %{
          "body" => "# Public incident\n\nA public account with enough detail.",
          "visibility" => "public"
        },
        owner
      )

    {:ok, private_postmortem} =
      Postmortems.publish_postmortem(
        %{
          "body" => "# Private incident\n\nA private account with enough detail.",
          "visibility" => "private"
        },
        owner
      )

    embed = fn _body -> {:ok, [0.8, 0.2]} end

    for postmortem <- [public_postmortem, private_postmortem] do
      assert {:ok, %Embedding{status: :indexed}} =
               Postmortems.index_postmortem(postmortem.id, content_hash(postmortem.body),
                 embed: embed
               )
    end

    assert {:ok, anonymous_results} = Postmortems.semantic_search("incident", embed: embed)
    assert Enum.map(anonymous_results, & &1.postmortem.id) == [public_postmortem.id]

    assert {:ok, member_results} =
             Postmortems.semantic_search("incident", embed: embed, user: owner)

    assert MapSet.new(member_results, & &1.postmortem.id) ==
             MapSet.new([public_postmortem.id, private_postmortem.id])
  end

  test "rolls back postmortem changes when domain assignment fails" do
    owner = user()
    original_body = "# Original incident\n\nThe original account has enough detail."

    {:ok, postmortem} =
      Postmortems.publish_postmortem(%{"body" => original_body}, owner)

    assert {:error, changeset} =
             Postmortems.update_postmortem(
               postmortem,
               %{
                 "body" => "# Changed incident\n\nThis change must be rolled back.",
                 "domain_ids" => [Ecto.UUID.generate()]
               },
               owner
             )

    assert {"contains unknown domains", _metadata} = changeset.errors[:domain_ids]
    assert Repo.get!(Postmortems.Postmortem, postmortem.id).body == original_body
  end

  test "preserves domains when a partial update omits domain identifiers" do
    owner = user()
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.create_project(%{name: "Postmortem project #{suffix}", visibility: :public})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Postmortem domain #{suffix}",
        project_id: project.id,
        visibility: :public
      })

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{
          "body" => "# Domain incident\n\nThe domain account has enough detail.",
          "domain_ids" => [domain.id]
        },
        owner
      )

    assert {:ok, _postmortem} =
             Postmortems.update_postmortem(
               postmortem,
               %{"body" => "# Domain incident\n\nThe account now has corrected details."},
               owner
             )

    assert [%{id: domain_id}] =
             Postmortems.get_postmortem_by_number!(postmortem.number).domains

    assert domain_id == domain.id
  end

  test "does not publish a postmortem that retains a private domain" do
    owner = user()
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.create_project(%{name: "Private project #{suffix}", visibility: :private})

    {:ok, domain} =
      Domains.create_domain(%{
        name: "Private domain #{suffix}",
        project_id: project.id,
        visibility: :private
      })

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{
          "body" => "# Private domain incident\n\nThe account has enough private detail.",
          "domain_ids" => [domain.id],
          "visibility" => "private"
        },
        owner
      )

    assert {:error, changeset} =
             Postmortems.update_postmortem(
               postmortem,
               %{"visibility" => "public"},
               owner
             )

    assert {"public postmortems can only include public domains", _metadata} =
             changeset.errors[:domain_ids]

    assert Repo.get!(Postmortems.Postmortem, postmortem.id).visibility == :private
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
               %{
                 "title" => "Add a registry latency alert",
                 "description" => "Page the registry team when latency crosses the threshold."
               },
               owner
             )

    assert action_item.description ==
             "Page the registry team when latency crosses the threshold."

    assert {:ok, action_item} =
             Postmortems.update_action_item(
               postmortem,
               action_item,
               %{
                 "title" => "Add a registry latency alert and runbook",
                 "description" => "Document the response steps next to the alert definition."
               },
               owner
             )

    assert action_item.description == "Document the response steps next to the alert definition."

    assert {:ok, %{completed_at: completed_at} = action_item} =
             Postmortems.toggle_action_item(postmortem, action_item, owner)

    assert completed_at

    assert {:ok, %{completed_at: nil} = action_item} =
             Postmortems.toggle_action_item(postmortem, action_item, owner)

    assert {:ok, _action_item} = Postmortems.delete_action_item(postmortem, action_item, owner)
  end

  test "records postmortem and action-item writes in the audit trail" do
    owner = user()

    {:ok, postmortem} =
      Postmortems.publish_postmortem(
        %{"body" => "# Audited incident\n\nThe audited account has enough detail."},
        owner
      )

    assert %Activity{actor_id: actor_id, metadata: %{"number" => number}} =
             Repo.get_by!(Activity,
               action: "postmortem.published",
               target_id: postmortem.id
             )

    assert actor_id == owner.id
    assert number == to_string(postmortem.number)

    assert {:ok, action_item} =
             Postmortems.create_action_item(
               postmortem,
               %{"title" => "Document the mitigation"},
               owner
             )

    assert %Activity{metadata: %{"action_item_id" => action_item_id}} =
             Repo.get_by!(Activity,
               action: "postmortem.action_item_created",
               target_id: postmortem.id
             )

    assert action_item_id == action_item.id
  end

  test "uses the first level-one Markdown heading as the title" do
    assert Postmortems.title(
             "Introduction\n\n## Not the title\n\n# Registry incident\n\nDetails."
           ) ==
             "Registry incident"
  end

  defp content_hash(body),
    do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
end
