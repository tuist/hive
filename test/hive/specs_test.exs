defmodule Hive.SpecsTest do
  use Hive.DataCase, async: true

  alias Hive.Accounts
  alias Hive.Forage
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
  end

  describe "list_specs/1" do
    test "filters specs by status" do
      user = user()
      {:ok, draft} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      {:ok, accepted} =
        Specs.create_spec(
          %{"title" => "Accepted", "body" => "Accepted proposal.", "status" => "accepted"},
          user
        )

      assert Enum.map(Specs.list_specs(status: :draft), & &1.id) == [draft.id]
      assert Enum.map(Specs.list_specs(status: :accepted), & &1.id) == [accepted.id]
      assert Enum.map(Specs.list_specs(status: {:not, :draft}), & &1.id) == [accepted.id]
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
  end
end
