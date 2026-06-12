defmodule Hive.SpecsTest do
  use Hive.DataCase, async: true
  use Mimic

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Forage
  alias Hive.Meadows
  alias Hive.Repo
  alias Hive.Specs

  defp user(email \\ "alice@example.com") do
    {:ok, user} =
      Accounts.upsert_from_auth(%{email: email, provider: "test", provider_uid: email})

    user
  end

  defp feature_request(user) do
    {:ok, feature_request} =
      Forage.create_feature_request(
        %{
          "title" => "GitHub sign-in",
          "description" => "Let requesters sign in with GitHub."
        },
        user
      )

    feature_request
  end

  describe "create_spec/2" do
    test "creates an editable proposal linked to a forage item" do
      user = user()
      feature_request = feature_request(user)

      assert {:ok, spec} =
               Specs.create_spec(
                 %{
                   "title" => "GitHub sign-in",
                   "body" => "Add GitHub sign-in for requesters.",
                   "source_feature_request_id" => feature_request.id
                 },
                 user
               )

      spec = Specs.get_spec!(spec.id)
      assert is_integer(spec.number)
      assert spec.status == :draft
      assert spec.lock_version == 1
      assert spec.source_feature_request.id == feature_request.id
      assert spec.created_by_user_id == user.id
      assert spec.updated_by_user_id == user.id

      assert [%{revision: 1, title: "GitHub sign-in", user: %{email: "alice@example.com"}}] =
               spec.revisions
    end

    test "rejects guests" do
      assert Specs.create_spec(%{"title" => "Nope", "body" => "This should not persist."}, nil) ==
               {:error, :unauthorized}
    end

    test "validates the agent-written summary" do
      assert {:error, changeset} =
               Specs.create_spec(
                 %{
                   "title" => "Nope",
                   "body" => "This should not persist.",
                   "summary" => "This summary has an em dash — reject it."
                 },
                 user()
               )

      assert {"cannot contain em dashes", []} = changeset.errors[:summary]
    end

    test "associates specs with meadows" do
      user = user()
      {:ok, meadow} = Meadows.create_meadow(%{name: "Hive"})

      assert {:ok, spec} =
               Specs.create_spec(
                 %{
                   "title" => "GitHub sign-in",
                   "body" => "Add GitHub sign-in for requesters.",
                   "meadow_ids" => [meadow.id]
                 },
                 user
               )

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.meadows, & &1.name) == ["Hive"]
    end
  end

  describe "get_spec_by_reference!/1" do
    test "accepts UUIDs, public numbers, and shared spec URLs" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      assert Specs.get_spec_by_reference!(spec.id).id == spec.id
      assert Specs.get_spec_by_reference!(Integer.to_string(spec.number)).id == spec.id
      assert Specs.get_spec_by_reference!("/specs/#{spec.number}").id == spec.id
      assert Specs.get_spec_by_reference!("https://hive.test/specs/#{spec.number}").id == spec.id

      assert Specs.get_spec_by_reference!("https://hive.test/specs/#{spec.number}/edit").id ==
               spec.id
    end
  end

  describe "list_specs/1" do
    test "filters specs by status" do
      user = user()
      {:ok, draft} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      {:ok, approved} =
        Specs.create_spec(
          %{"title" => "Approved", "body" => "Approved proposal.", "status" => "approved"},
          user
        )

      assert Enum.map(Specs.list_specs(status: :draft), & &1.id) == [draft.id]
      assert Enum.map(Specs.list_specs(status: :approved), & &1.id) == [approved.id]
      assert Enum.map(Specs.list_specs(status: {:not, :draft}), & &1.id) == [approved.id]
    end

    test "hides private specs from non-members" do
      member = user("member@tuist.dev")
      contributor = user("contributor@example.com")

      {:ok, public} =
        Specs.create_spec(
          %{"title" => "Public", "body" => "Initial proposal.", "visibility" => "public"},
          member
        )

      {:ok, private} =
        Specs.create_spec(
          %{"title" => "Private", "body" => "Initial proposal.", "visibility" => "private"},
          member
        )

      stub(Auth, :member?, fn
        %{email: "member@tuist.dev"} -> true
        _user -> false
      end)

      assert Specs.list_specs(user: member) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([private.id, public.id])

      assert Enum.map(Specs.list_specs(user: contributor), & &1.id) == [public.id]
      assert Enum.map(Specs.list_specs(user: nil), & &1.id) == [public.id]
    end

    test "uses spec visibility before meadow visibility" do
      member = user("member@tuist.dev")
      contributor = user("contributor@example.com")
      {:ok, public_meadow} = Meadows.create_meadow(%{name: "Hive", visibility: "public"})
      {:ok, private_meadow} = Meadows.create_meadow(%{name: "Atlas", visibility: "private"})

      {:ok, public_spec_on_private_meadow} =
        Specs.create_spec(
          %{
            "title" => "Public spec",
            "body" => "Initial proposal.",
            "visibility" => "public",
            "meadow_ids" => [private_meadow.id]
          },
          member
        )

      {:ok, private_spec_on_public_meadow} =
        Specs.create_spec(
          %{
            "title" => "Private spec",
            "body" => "Initial proposal.",
            "visibility" => "private",
            "meadow_ids" => [public_meadow.id]
          },
          member
        )

      stub(Auth, :member?, fn
        %{email: "member@tuist.dev"} -> true
        _user -> false
      end)

      assert Specs.can_view?(Specs.get_spec!(public_spec_on_private_meadow.id), member)
      assert Specs.can_view?(Specs.get_spec!(public_spec_on_private_meadow.id), contributor)
      assert Specs.can_view?(Specs.get_spec!(public_spec_on_private_meadow.id), nil)
      refute Specs.can_view?(Specs.get_spec!(private_spec_on_public_meadow.id), contributor)
      refute Specs.can_view?(Specs.get_spec!(private_spec_on_public_meadow.id), nil)

      assert Specs.effective_visibility(Specs.get_spec!(public_spec_on_private_meadow.id)) ==
               :public

      assert Specs.effective_visibility(Specs.get_spec!(private_spec_on_public_meadow.id)) ==
               :private

      assert Specs.list_specs(user: member) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([private_spec_on_public_meadow.id, public_spec_on_private_meadow.id])

      assert Enum.map(Specs.list_specs(user: contributor), & &1.id) == [
               public_spec_on_private_meadow.id
             ]

      assert Enum.map(Specs.list_specs(user: nil), & &1.id) == [
               public_spec_on_private_meadow.id
             ]
    end
  end

  describe "update_spec/3" do
    test "updates member-editable fields and increments the revision" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      assert {:ok, spec} =
               Specs.update_spec(
                 spec,
                 %{"title" => "Updated", "body" => "Updated proposal.", "status" => "proposed"},
                 user
               )

      assert spec.title == "Updated"
      assert spec.status == :proposed
      assert spec.lock_version == 2

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.revisions, & &1.revision) == [2, 1]
      assert Enum.map(spec.revisions, & &1.title) == ["Updated", "Draft"]
    end

    test "returns a stale changeset when the local copy is outdated" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
      stale_spec = Repo.get!(Hive.Specs.Spec, spec.id)

      {:ok, _spec} = Specs.update_spec(spec, %{"title" => "Remote edit"}, user)

      assert {:error, changeset} = Specs.update_spec(stale_spec, %{"title" => "Local edit"}, user)
      assert [lock_version: {"is stale", [stale: true]}] = changeset.errors
    end

    test "updates associated meadows" do
      user = user()
      {:ok, hive} = Meadows.create_meadow(%{name: "Hive"})
      {:ok, noora} = Meadows.create_meadow(%{name: "Noora"})

      {:ok, spec} =
        Specs.create_spec(
          %{
            "title" => "Draft",
            "body" => "Initial proposal.",
            "meadow_ids" => [hive.id]
          },
          user
        )

      assert {:ok, spec} =
               Specs.update_spec(
                 spec,
                 %{
                   "title" => "Draft",
                   "body" => "Initial proposal.",
                   "meadow_ids" => [noora.id]
                 },
                 user
               )

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.meadows, & &1.name) == ["Noora"]
    end
  end

  describe "comments" do
    test "requires authentication" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      assert Specs.add_comment(spec, %{"author_name" => "Guest", "body" => "Looks useful."}) ==
               {:error, :unauthorized}

      assert {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Ship it."}, user)

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.comments, & &1.body) == ["Ship it."]
      assert Enum.at(spec.comments, 0).user.email == user.email
    end

    test "rejects comments on private specs from non-members" do
      member = user("member@tuist.dev")
      contributor = user("contributor@example.com")

      {:ok, spec} =
        Specs.create_spec(
          %{"title" => "Private", "body" => "Initial proposal.", "visibility" => "private"},
          member
        )

      stub(Auth, :member?, fn
        %{email: "member@tuist.dev"} -> true
        _user -> false
      end)

      assert Specs.add_comment(spec, %{"body" => "Can I see this?"}, contributor) ==
               {:error, :unauthorized}

      assert {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Member note."}, member)
    end
  end
end
