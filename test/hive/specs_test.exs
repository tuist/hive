defmodule Hive.SpecsTest do
  use Hive.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Hive.Repo

  alias Hive.Accounts
  alias Hive.Auth
  alias Hive.Forage
  alias Hive.Domains
  alias Hive.Projects
  alias Hive.Repo
  alias Hive.Slack.Installation
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

  defp slack_notifications!(event) do
    suffix = System.unique_integer([:positive])

    {:ok, _installation} =
      %Installation{}
      |> Installation.changeset(%{
        team_id: "T#{suffix}",
        team_name: "Workspace #{suffix}",
        bot_token: "xoxb-#{suffix}",
        installed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        notification_channel_id: "C#{suffix}",
        notification_events: [event]
      })
      |> Repo.insert()
  end

  defp create_domain!(attrs) do
    {:ok, project} =
      Projects.create_project(%{name: "Project #{System.unique_integer([:positive])}"})

    attrs = Map.put_new(attrs, :project_id, project.id)
    {:ok, domain} = Domains.create_domain(attrs)
    domain
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

    test "validates the spec summary" do
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

    test "associates specs with domains" do
      user = user()
      domain = create_domain!(%{name: "Hive"})

      assert {:ok, spec} =
               Specs.create_spec(
                 %{
                   "title" => "GitHub sign-in",
                   "body" => "Add GitHub sign-in for requesters.",
                   "domain_ids" => [domain.id]
                 },
                 user
               )

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.domains, & &1.name) == ["Hive"]
    end

    test "enqueues a Slack notification when configured" do
      user = user()
      slack_notifications!("spec.created")

      assert {:ok, spec} =
               Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      assert_enqueued(
        worker: Hive.Slack.Workers.SendNotification,
        args: %{"event" => "spec.created", "spec_id" => spec.id}
      )
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
          %{"title" => "Public", "body" => "Initial proposal."},
          member
        )

      {:ok, private} =
        Specs.create_spec(
          %{
            "title" => "Private",
            "body" => "Initial proposal.",
            "visibility_override" => "private"
          },
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

    test "inherits visibility from the project and only allows private overrides" do
      member = user("member@tuist.dev")
      contributor = user("contributor@example.com")
      {:ok, public_project} = Projects.create_project(%{name: "Hive", visibility: "public"})
      {:ok, private_project} = Projects.create_project(%{name: "Atlas", visibility: "private"})

      private_domain =
        create_domain!(%{
          name: "Private domain",
          project_id: public_project.id,
          visibility: "private"
        })

      public_domain =
        create_domain!(%{
          name: "Public domain",
          project_id: private_project.id,
          visibility: "public"
        })

      {:ok, public_project_spec} =
        Specs.create_spec(
          %{
            "title" => "Public spec",
            "body" => "Initial proposal.",
            "project_id" => public_project.id,
            "domain_ids" => [private_domain.id]
          },
          member
        )

      {:ok, private_project_spec} =
        Specs.create_spec(
          %{
            "title" => "Private project spec",
            "body" => "Initial proposal.",
            "project_id" => private_project.id,
            "visibility" => "public",
            "domain_ids" => [public_domain.id]
          },
          member
        )

      {:ok, private_override_spec} =
        Specs.create_spec(
          %{
            "title" => "Private override spec",
            "body" => "Initial proposal.",
            "project_id" => public_project.id,
            "visibility_override" => "private"
          },
          member
        )

      stub(Auth, :member?, fn
        %{email: "member@tuist.dev"} -> true
        _user -> false
      end)

      assert Specs.can_view?(Specs.get_spec!(public_project_spec.id), member)
      assert Specs.can_view?(Specs.get_spec!(public_project_spec.id), contributor)
      assert Specs.can_view?(Specs.get_spec!(public_project_spec.id), nil)
      refute Specs.can_view?(Specs.get_spec!(private_project_spec.id), contributor)
      refute Specs.can_view?(Specs.get_spec!(private_project_spec.id), nil)
      refute Specs.can_view?(Specs.get_spec!(private_override_spec.id), contributor)
      refute Specs.can_view?(Specs.get_spec!(private_override_spec.id), nil)

      assert Specs.effective_visibility(Specs.get_spec!(public_project_spec.id)) == :public
      assert Specs.effective_visibility(Specs.get_spec!(private_project_spec.id)) == :private
      assert Specs.effective_visibility(Specs.get_spec!(private_override_spec.id)) == :private

      assert Specs.list_specs(user: member) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([
                 private_project_spec.id,
                 private_override_spec.id,
                 public_project_spec.id
               ])

      assert Enum.map(Specs.list_specs(user: contributor), & &1.id) == [public_project_spec.id]

      assert Enum.map(Specs.list_specs(user: nil), & &1.id) == [public_project_spec.id]
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

    test "updates associated domains" do
      user = user()

      {:ok, project} =
        Projects.create_project(%{name: "Specs #{System.unique_integer([:positive])}"})

      hive = create_domain!(%{name: "Hive", project_id: project.id})
      noora = create_domain!(%{name: "Noora", project_id: project.id})

      {:ok, spec} =
        Specs.create_spec(
          %{
            "title" => "Draft",
            "body" => "Initial proposal.",
            "domain_ids" => [hive.id]
          },
          user
        )

      assert {:ok, spec} =
               Specs.update_spec(
                 spec,
                 %{
                   "title" => "Draft",
                   "body" => "Initial proposal.",
                   "domain_ids" => [noora.id]
                 },
                 user
               )

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.domains, & &1.name) == ["Noora"]
    end

    test "removes domains that do not belong to a changed project" do
      user = user()

      {:ok, old_project} =
        Projects.create_project(%{name: "Old #{System.unique_integer([:positive])}"})

      {:ok, new_project} =
        Projects.create_project(%{name: "New #{System.unique_integer([:positive])}"})

      domain = create_domain!(%{name: "Hive", project_id: old_project.id})

      {:ok, spec} =
        Specs.create_spec(
          %{
            "title" => "Draft",
            "body" => "Initial proposal.",
            "project_id" => old_project.id,
            "domain_ids" => [domain.id]
          },
          user
        )

      assert {:ok, spec} =
               Specs.update_spec(
                 spec,
                 %{
                   "title" => "Draft",
                   "body" => "Initial proposal.",
                   "project_id" => new_project.id
                 },
                 user
               )

      spec = Specs.get_spec!(spec.id)
      assert spec.project_id == new_project.id
      assert spec.domains == []
    end
  end

  describe "request_review/2" do
    test "enqueues a Slack review request notification when configured" do
      user = user()
      slack_notifications!("spec.review.requested")
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      assert {:ok, _spec} = Specs.request_review(spec, user)

      assert_enqueued(
        worker: Hive.Slack.Workers.SendNotification,
        args: %{
          "event" => "spec.review.requested",
          "spec_id" => spec.id,
          "requester_id" => user.id
        }
      )
    end

    test "returns a configuration error when no Slack review target is enabled" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      assert Specs.request_review(spec, user) == {:error, :slack_notifications_not_configured}
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
          %{
            "title" => "Private",
            "body" => "Initial proposal.",
            "visibility_override" => "private"
          },
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

    test "accepts a body at the maximum length and rejects one beyond it" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      assert {:ok, _comment} =
               Specs.add_comment(spec, %{"body" => String.duplicate("a", 20_000)}, user)

      assert {:error, changeset} =
               Specs.add_comment(spec, %{"body" => String.duplicate("a", 20_001)}, user)

      assert {"should be at most %{count} character(s)",
              [count: 20_000, validation: :length, kind: :max, type: :string]} =
               changeset.errors[:body]
    end

    test "enqueues a Slack notification when configured" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
      slack_notifications!("spec.comment.created")

      assert {:ok, comment} = Specs.add_comment(spec, %{"body" => "Looks useful."}, user)

      assert_enqueued(
        worker: Hive.Slack.Workers.SendNotification,
        args: %{"event" => "spec.comment.created", "comment_id" => comment.id}
      )
    end

    test "updates comments for their author" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
      {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, user)

      assert {:ok, updated_comment} =
               Specs.update_comment(comment, %{"body" => "Updated note."}, user)

      assert updated_comment.body == "Updated note."
    end

    test "rejects comment updates from other users" do
      author = user("author@example.com")
      other_user = user("other@example.com")

      {:ok, spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, author)

      assert Specs.update_comment(comment, %{"body" => "Hijacked."}, other_user) ==
               {:error, :unauthorized}

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.comments, & &1.body) == ["Initial note."]
    end

    test "deletes comments for their author" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
      {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, user)

      assert {:ok, _comment} = Specs.delete_comment(comment, user)

      spec = Specs.get_spec!(spec.id)
      assert spec.comments == []
    end

    test "rejects comment deletes from other users" do
      author = user("delete-author@example.com")
      other_user = user("delete-other@example.com")

      {:ok, spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      {:ok, comment} = Specs.add_comment(spec, %{"body" => "Initial note."}, author)

      assert Specs.delete_comment(comment, other_user) == {:error, :unauthorized}

      spec = Specs.get_spec!(spec.id)
      assert Enum.map(spec.comments, & &1.body) == ["Initial note."]
    end
  end

  describe "mark_viewed/2 and new-activity surfacing" do
    test "no activity badge before the user has ever opened the spec" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      [listed] = Specs.list_specs(user: user)
      assert listed.id == spec.id
      assert listed.has_new_activity == false
      assert listed.last_activity_at == Repo.get!(Specs.Spec, spec.id).updated_at
    end

    test "no activity badge right after the user opens the spec" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)
      :ok = Specs.mark_viewed(spec, user)

      [listed] = Specs.list_specs(user: user)
      assert listed.has_new_activity == false
    end

    test "shows activity when the spec is edited after the user last viewed it" do
      author = user("author@example.com")
      reader = user("reader@example.com")

      {:ok, spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      :ok = Specs.mark_viewed(spec, reader)

      backdate_view(reader.id, spec.id, ~U[2020-01-01 00:00:00.000000Z])

      {:ok, _spec} = Specs.update_spec(spec, %{"title" => "Updated"}, author)

      [listed] = Specs.list_specs(user: reader)
      assert listed.has_new_activity == true
    end

    test "shows activity when a new comment lands after the user last viewed the spec" do
      author = user("author@example.com")
      reader = user("reader@example.com")

      {:ok, spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      :ok = Specs.mark_viewed(spec, reader)

      backdate_view(reader.id, spec.id, ~U[2020-01-01 00:00:00.000000Z])

      {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Late note."}, author)

      [listed] = Specs.list_specs(user: reader)
      assert listed.has_new_activity == true
    end

    test "anonymous viewers never see the activity badge" do
      author = user("author@example.com")

      {:ok, _spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      [listed] = Specs.list_specs(user: nil)
      assert listed.has_new_activity == false
    end

    test "upserting a view twice keeps a single row and advances the timestamp" do
      user = user()
      {:ok, spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      :ok = Specs.mark_viewed(spec, user)
      backdate_view(user.id, spec.id, ~U[2020-01-01 00:00:00.000000Z])
      :ok = Specs.mark_viewed(spec, user)

      views = Repo.all(Specs.View)
      assert length(views) == 1
      [view] = views
      assert DateTime.compare(view.last_viewed_at, ~U[2020-01-01 00:00:00.000000Z]) == :gt
    end

    test "has_new_activity_for_user? returns false when the user has no views" do
      user = user()
      {:ok, _spec} = Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, user)

      refute Specs.has_new_activity_for_user?(user)
    end

    test "has_new_activity_for_user? returns false for anonymous users" do
      author = user()

      {:ok, _spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      refute Specs.has_new_activity_for_user?(nil)
    end

    test "has_new_activity_for_user? returns true after a spec edit lands" do
      author = user("author@example.com")
      reader = user("reader@example.com")

      {:ok, spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      :ok = Specs.mark_viewed(spec, reader)
      backdate_view(reader.id, spec.id, ~U[2020-01-01 00:00:00.000000Z])
      {:ok, _spec} = Specs.update_spec(spec, %{"title" => "Updated"}, author)

      assert Specs.has_new_activity_for_user?(reader)
    end

    test "has_new_activity_for_user? returns true after a new comment lands" do
      author = user("author@example.com")
      reader = user("reader@example.com")

      {:ok, spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      :ok = Specs.mark_viewed(spec, reader)
      backdate_view(reader.id, spec.id, ~U[2020-01-01 00:00:00.000000Z])
      {:ok, _comment} = Specs.add_comment(spec, %{"body" => "Late note."}, author)

      assert Specs.has_new_activity_for_user?(reader)
    end

    test "has_new_activity_for_user? stays false once the user catches up" do
      author = user("author@example.com")
      reader = user("reader@example.com")

      {:ok, spec} =
        Specs.create_spec(%{"title" => "Draft", "body" => "Initial proposal."}, author)

      :ok = Specs.mark_viewed(spec, reader)

      refute Specs.has_new_activity_for_user?(reader)
    end
  end

  defp backdate_view(user_id, spec_id, datetime) do
    {1, _} =
      Repo.update_all(
        from(view in Specs.View,
          where: view.user_id == ^user_id and view.spec_id == ^spec_id
        ),
        set: [last_viewed_at: datetime]
      )
  end
end
