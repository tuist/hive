defmodule Hive.Specs do
  @moduledoc """
  Editable domain proposals that can be shaped from forage.
  """

  import Ecto.Query

  require Logger

  alias Ecto.Changeset
  alias Hive.Accounts.User
  alias Hive.Audit
  alias Hive.Auth
  alias Hive.Domains.Domain
  alias Hive.Notifications
  alias Hive.Projects.Project
  alias Hive.Projects.ProjectDomain
  alias Hive.Repo
  alias Hive.Specs.Comment
  alias Hive.Specs.Revision
  alias Hive.Specs.Spec
  alias Hive.Specs.View
  alias Hive.Slack
  alias Hive.Slack.Workers.SendNotification

  @pubsub Hive.PubSub
  @topic_prefix "specs"
  @spec_number_lock_namespace 0x48695645
  @spec_number_lock_key 0x53504353

  # Bound how long a spec write blocks acquiring the spec-numbering advisory lock
  # or a contended row lock. Without it a stuck or abandoned writer wedges every
  # subsequent write indefinitely: idle_in_transaction_session_timeout only clears
  # a holder that has gone idle, and lock_timeout is the only bound that also
  # covers the pg_advisory_xact_lock acquisition.
  @write_lock_timeout_ms 10_000

  def can_create?(user), do: Auth.member?(user)
  def can_edit?(_spec, user), do: Auth.member?(user)
  def can_request_review?(%Spec{} = spec, user), do: can_edit?(spec, user)
  def can_comment?(spec, %User{} = user), do: can_view?(spec, user)
  def can_comment?(_spec, _user), do: false

  def can_edit_comment?(%Comment{user_id: user_id}, %User{id: user_id}) when is_binary(user_id),
    do: true

  def can_edit_comment?(_comment, _user), do: false

  def can_view?(%Spec{} = spec, user),
    do: Auth.member?(user) or effective_visibility(spec) == :public

  def subscribe_to_spec(%Spec{id: id}), do: subscribe_to_spec(id)

  def subscribe_to_spec(id) when is_binary(id) do
    Phoenix.PubSub.subscribe(@pubsub, spec_topic(id))
  end

  def effective_visibility(%Spec{visibility_override: :private}), do: :private

  def effective_visibility(%Spec{project: %Project{visibility: visibility}})
      when visibility in [:public, :private],
      do: visibility

  def effective_visibility(%Spec{project: %Ecto.Association.NotLoaded{}, project_id: project_id})
      when is_binary(project_id) do
    case Repo.get(Project, project_id) do
      %Project{visibility: visibility} -> visibility
      nil -> :private
    end
  end

  def effective_visibility(%Spec{} = spec) do
    if spec.project_id, do: :private, else: :public
  end

  def list_specs(opts \\ []) do
    status = Keyword.get(opts, :status)
    user = Keyword.get(opts, :user)

    specs =
      Spec
      |> maybe_filter_by_status(status)
      |> maybe_filter_by_visibility(user)
      |> order_by([spec], desc: spec.updated_at)
      |> preload([
        :project,
        :source_feature_request,
        :created_by_user,
        :updated_by_user,
        :domains
      ])
      |> Repo.all()

    decorate_with_activity(specs, user)
  end

  def mark_viewed(%Spec{id: spec_id}, %User{id: user_id})
      when is_binary(spec_id) and is_binary(user_id) do
    now = DateTime.utc_now()

    %View{}
    |> Ecto.Changeset.cast(
      %{spec_id: spec_id, user_id: user_id, last_viewed_at: now},
      [:spec_id, :user_id, :last_viewed_at]
    )
    |> Repo.insert(
      on_conflict: [set: [last_viewed_at: now, updated_at: DateTime.truncate(now, :second)]],
      conflict_target: [:user_id, :spec_id]
    )

    :ok
  end

  def mark_viewed(_spec, _user), do: :ok

  def last_viewed_at(%Spec{id: spec_id}, %User{id: user_id})
      when is_binary(spec_id) and is_binary(user_id) do
    Repo.one(
      from(view in View,
        where: view.user_id == ^user_id and view.spec_id == ^spec_id,
        select: view.last_viewed_at
      )
    )
  end

  def last_viewed_at(_spec, _user), do: nil

  def has_new_activity_for_user?(%User{id: user_id}) when is_binary(user_id) do
    from(view in View,
      as: :view,
      join: spec in Spec,
      on: spec.id == view.spec_id,
      where: view.user_id == ^user_id,
      where:
        spec.updated_at > view.last_viewed_at or
          exists(
            from(comment in Comment,
              where:
                comment.spec_id == parent_as(:view).spec_id and
                  comment.inserted_at > parent_as(:view).last_viewed_at
            )
          )
    )
    |> Repo.exists?()
  end

  def has_new_activity_for_user?(_user), do: false

  defp decorate_with_activity(specs, _user) when specs == [], do: []

  defp decorate_with_activity(specs, user) do
    spec_ids = Enum.map(specs, & &1.id)
    last_comment_at = last_comment_inserted_at(spec_ids)
    last_viewed_at = last_viewed_at_by_user(spec_ids, user)

    Enum.map(specs, fn spec ->
      last_activity_at = latest_datetime(spec.updated_at, Map.get(last_comment_at, spec.id))
      viewed_at = Map.get(last_viewed_at, spec.id)

      has_new_activity =
        not is_nil(viewed_at) and
          DateTime.compare(last_activity_at, viewed_at) == :gt

      %{spec | last_activity_at: last_activity_at, has_new_activity: has_new_activity}
    end)
  end

  defp last_comment_inserted_at(spec_ids) do
    from(comment in Comment,
      where: comment.spec_id in ^spec_ids,
      group_by: comment.spec_id,
      select: {comment.spec_id, max(comment.inserted_at)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp last_viewed_at_by_user(spec_ids, %User{id: user_id}) when is_binary(user_id) do
    from(view in View,
      where: view.user_id == ^user_id and view.spec_id in ^spec_ids,
      select: {view.spec_id, view.last_viewed_at}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp last_viewed_at_by_user(_spec_ids, _user), do: %{}

  defp latest_datetime(nil, nil), do: nil
  defp latest_datetime(a, nil), do: a
  defp latest_datetime(nil, b), do: b

  defp latest_datetime(a, b) do
    if DateTime.compare(a, b) == :lt, do: b, else: a
  end

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, {:not, status}) do
    if status in Spec.statuses(),
      do: where(query, [spec], spec.status != ^status),
      else: query
  end

  defp maybe_filter_by_status(query, status) do
    if status in Spec.statuses(),
      do: where(query, [spec], spec.status == ^status),
      else: query
  end

  defp maybe_filter_by_visibility(query, user) do
    if Auth.member?(user) do
      query
    else
      where(
        join(query, :left, [spec], project in assoc(spec, :project)),
        [spec, project],
        is_nil(spec.visibility_override) and
          (project.visibility == :public or is_nil(spec.project_id))
      )
    end
  end

  def get_spec!(id) do
    Spec
    |> preload_spec()
    |> Repo.get!(id)
  end

  def get_spec_by_number!(number) when is_integer(number) do
    Spec
    |> preload_spec()
    |> Repo.get_by!(number: number)
  end

  def get_spec_by_number!(number) when is_binary(number) do
    case Integer.parse(number) do
      {number, ""} -> get_spec_by_number!(number)
      _invalid -> raise Ecto.NoResultsError, queryable: Spec
    end
  end

  def get_spec_by_reference!(reference) when is_integer(reference),
    do: get_spec_by_number!(reference)

  def get_spec_by_reference!(reference) when is_binary(reference) do
    reference
    |> reference_identifier()
    |> case do
      identifier when identifier == "" ->
        raise Ecto.NoResultsError, queryable: Spec

      identifier ->
        if public_number?(identifier),
          do: get_spec_by_number!(identifier),
          else: get_spec!(identifier)
    end
  end

  defp reference_identifier(reference) do
    reference = String.trim(reference)

    case URI.parse(reference) do
      %URI{path: path} when is_binary(path) and path != "" ->
        path
        |> String.split("/", trim: true)
        |> spec_path_number()
        |> Kernel.||(reference)

      _uri ->
        reference
    end
  end

  defp spec_path_number(["specs", number | _rest]), do: number
  defp spec_path_number([_segment | rest]), do: spec_path_number(rest)
  defp spec_path_number([]), do: nil

  defp public_number?(identifier) do
    match?({_number, ""}, Integer.parse(identifier))
  end

  defp preload_spec(query) do
    comments_query =
      from(comment in Comment, order_by: [asc: comment.inserted_at], preload: [user: :identities])

    revisions_query =
      from(revision in Revision,
        order_by: [desc: revision.revision],
        preload: [user: :identities]
      )

    preload(query, [
      :project,
      :source_feature_request,
      :created_by_user,
      :updated_by_user,
      :domains,
      comments: ^comments_query,
      revisions: ^revisions_query
    ])
  end

  def change_spec(spec \\ %Spec{}, attrs \\ %{}) do
    spec
    |> preload_for_form()
    |> Spec.changeset(attrs)
    |> maybe_put_existing_domain_ids(attrs)
  end

  def create_spec(attrs, %User{} = user) do
    if can_create?(user) do
      write_transaction(fn -> create_spec_transaction(attrs, user) end)
      |> case do
        {:ok, spec} ->
          record_spec_event("spec.created", spec, user)
          enqueue_slack_notification("spec.created", %{"spec_id" => spec.id})
          Hive.Domains.schedule_evolution()
          {:ok, spec}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized}
    end
  end

  def create_spec(_attrs, _user), do: {:error, :unauthorized}

  def update_spec(%Spec{} = spec, attrs, %User{} = user) do
    if can_edit?(spec, user) do
      write_transaction(fn -> update_spec_transaction(spec, attrs, user) end)
      |> case do
        {:ok, updated_spec} ->
          record_spec_event("spec.updated", updated_spec, user)
          Hive.Domains.schedule_evolution()
          {:ok, updated_spec}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized}
    end
  end

  def update_spec(_spec, _attrs, _user), do: {:error, :unauthorized}

  def request_review(%Spec{} = spec, %User{} = user) do
    cond do
      not can_request_review?(spec, user) ->
        {:error, :unauthorized}

      # Without a channel the request would be recorded and then reach
      # nobody, so say so instead of reporting a review that never went out.
      not review_request_deliverable?() ->
        {:error, :notifications_not_configured}

      true ->
        Notifications.ensure_spec_follow(user, spec.id)

        Notifications.publish!(%{
          deduplication_key: "spec_review_requested:#{spec.id}:#{Ecto.UUID.generate()}",
          type: :spec_review_requested,
          resource_type: "spec",
          resource_id: spec.id,
          actor_id: user.id
        })

        enqueue_slack_notification("spec.review.requested", %{
          "spec_id" => spec.id,
          "requester_id" => user.id
        })

        record_spec_event("spec.review.requested", spec, user)
        {:ok, spec}
    end
  end

  def request_review(_spec, _user), do: {:error, :unauthorized}

  defp review_request_deliverable? do
    Slack.notification_enabled_for?("spec.review.requested") or Notifications.email_enabled?()
  end

  defp enqueue_slack_notification(event, args) do
    case SendNotification.enqueue(event, args) do
      {:error, reason} ->
        Logger.warning(
          "Slack notification for #{event} could not be enqueued: #{inspect(reason)}. " <>
            "Args: #{inspect(args)}"
        )

      _enqueued_or_skipped ->
        :ok
    end
  end

  # Runs a spec write inside a transaction that fails fast on lock contention
  # instead of hanging. lock_timeout bounds both the numbering advisory lock and
  # the optimistic-lock row update; a timeout surfaces as {:error, :locked} so
  # callers can prompt a retry rather than crash.
  defp write_transaction(fun) do
    Repo.transaction(fn ->
      Repo.query!("SET LOCAL lock_timeout = #{@write_lock_timeout_ms}")
      fun.()
    end)
  rescue
    error in Postgrex.Error ->
      if lock_not_available?(error),
        do: {:error, :locked},
        else: reraise(error, __STACKTRACE__)
  end

  defp lock_not_available?(%Postgrex.Error{postgres: %{code: :lock_not_available}}), do: true
  defp lock_not_available?(_error), do: false

  defp create_spec_transaction(attrs, user) do
    attrs = maybe_put_project_id(attrs)

    with {:ok, spec} <-
           %Spec{}
           |> Spec.changeset(attrs)
           |> Changeset.put_change(:created_by_user_id, user.id)
           |> Changeset.put_change(:updated_by_user_id, user.id)
           |> put_next_spec_number()
           |> Repo.insert(),
         {:ok, spec} <- put_domains(spec, attrs),
         {:ok, _revision} <- create_revision(spec, user) do
      publish_spec_creation(spec, user)
      spec
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp publish_spec_creation(spec, user) do
    Notifications.ensure_spec_follow(user, spec.id)

    Notifications.publish!(%{
      deduplication_key: "spec_created:#{spec.id}",
      type: :spec_created,
      resource_type: "spec",
      resource_id: spec.id,
      actor_id: user.id,
      data: %{"title" => spec.title}
    })

    if spec.source_feature_request_id, do: publish_source_spec_creation(spec, user)
  end

  # Runs inside the transaction that holds the spec-numbering advisory lock,
  # so the fan-out stays at a fixed number of queries no matter how many
  # people follow the item.
  defp publish_source_spec_creation(spec, user) do
    item_id = "manual:#{spec.source_feature_request_id}"
    spec_with_project = Repo.preload(spec, :project)

    Notifications.followers(:forage_item_updates, item_id)
    |> Enum.filter(&can_view?(spec_with_project, &1.user))
    |> Enum.map(&{&1.user_id, &1.cadence})
    |> Notifications.ensure_spec_follows(spec.id)

    Notifications.publish!(%{
      deduplication_key: "forage_spec_created:#{spec.id}",
      type: :forage_spec_created,
      resource_type: "forage_item",
      resource_id: item_id,
      actor_id: user.id,
      data: %{"spec_id" => spec.id, "spec_title" => spec.title}
    })
  end

  defp put_next_spec_number(%Changeset{valid?: true} = changeset) do
    lock_specs_for_numbering()
    Changeset.put_change(changeset, :number, next_spec_number())
  end

  defp put_next_spec_number(%Changeset{} = changeset), do: changeset

  defp lock_specs_for_numbering do
    Repo.query!(
      "SELECT pg_advisory_xact_lock($1::integer, $2::integer)",
      [@spec_number_lock_namespace, @spec_number_lock_key]
    )
  end

  defp next_spec_number do
    Repo.one!(from(spec in Spec, select: fragment("COALESCE(MAX(?), 0) + 1", spec.number)))
  end

  defp maybe_put_project_id(attrs) when is_map(attrs) do
    if project_id_present?(attrs) do
      attrs
    else
      project_id = inferred_project_id(attrs) || fallback_project_id()

      if project_id do
        Map.put(attrs, project_id_key(attrs), project_id)
      else
        attrs
      end
    end
  end

  defp maybe_put_project_id(attrs), do: attrs

  defp project_id_present?(attrs) do
    present?(Map.get(attrs, "project_id")) or present?(Map.get(attrs, :project_id))
  end

  defp project_id_key(attrs) do
    if Enum.any?(Map.keys(attrs), &is_binary/1), do: "project_id", else: :project_id
  end

  defp inferred_project_id(attrs) do
    case normalized_domain_ids(attrs) do
      [] ->
        nil

      domain_ids ->
        ProjectDomain
        |> where([project_domain], project_domain.domain_id in ^domain_ids)
        |> select([project_domain], project_domain.project_id)
        |> distinct(true)
        |> Repo.all()
        |> case do
          [project_id] -> project_id
          _project_ids -> nil
        end
    end
  end

  defp fallback_project_id do
    Project
    |> order_by([project], asc: project.inserted_at)
    |> limit(2)
    |> select([project], project.id)
    |> Repo.all()
    |> case do
      [project_id] -> project_id
      [] -> create_default_project_id()
      _project_ids -> nil
    end
  end

  defp create_default_project_id do
    case %Project{}
         |> Project.changeset(%{name: "Default project"})
         |> Repo.insert(
           on_conflict: :nothing,
           conflict_target: :name,
           returning: true
         ) do
      {:ok, %Project{id: id}} when is_binary(id) ->
        id

      {:ok, _project} ->
        Repo.get_by!(Project, name: "Default project").id

      {:error, _changeset} ->
        nil
    end
  end

  defp update_spec_transaction(spec, attrs, user) do
    with {:ok, spec} <-
           spec
           |> Spec.update_changeset(attrs)
           |> Changeset.put_change(:updated_by_user_id, user.id)
           |> Repo.update(stale_error_field: :lock_version),
         {:ok, spec} <- put_domains(spec, attrs),
         {:ok, revision} <- create_revision(spec, user) do
      Notifications.publish!(%{
        deduplication_key: "spec_updated:#{spec.id}:#{revision.id}",
        type: :spec_updated,
        resource_type: "spec",
        resource_id: spec.id,
        actor_id: user.id,
        data: %{"description" => spec.summary || spec.body}
      })

      spec
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def change_comment(comment \\ %Comment{}, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end

  def get_comment!(id) do
    Repo.get!(Comment, id)
  end

  def add_comment(spec, attrs, user \\ nil)

  def add_comment(%Spec{} = spec, attrs, %User{} = user) do
    if can_comment?(spec, user) do
      add_comment_transaction(spec, attrs, user)
      |> case do
        {:ok, comment} ->
          SendNotification.enqueue("spec.comment.created", %{"comment_id" => comment.id})
          {:ok, comment}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized}
    end
  end

  def add_comment(_spec, _attrs, _user), do: {:error, :unauthorized}

  defp add_comment_transaction(spec, attrs, user) do
    Repo.transaction(fn ->
      comment =
        %Comment{}
        |> Comment.changeset(attrs)
        |> Changeset.put_change(:spec_id, spec.id)
        |> Changeset.put_change(:user_id, user.id)
        |> Repo.insert()
        |> unwrap_or_rollback()

      Notifications.ensure_spec_follow(user, spec.id)

      Notifications.publish!(%{
        deduplication_key: "spec_comment_created:#{comment.id}",
        type: :spec_comment_created,
        resource_type: "spec",
        resource_id: spec.id,
        actor_id: user.id,
        data: %{"comment_preview" => String.slice(comment.body, 0, 500)}
      })

      comment
    end)
  end

  def update_comment(%Comment{} = comment, attrs, %User{} = user) do
    if can_edit_comment?(comment, user) do
      comment
      |> Comment.changeset(attrs)
      |> Repo.update()
    else
      {:error, :unauthorized}
    end
  end

  def update_comment(_comment, _attrs, _user), do: {:error, :unauthorized}

  def delete_comment(%Comment{} = comment, %User{} = user) do
    if can_edit_comment?(comment, user) do
      Repo.delete(comment)
    else
      {:error, :unauthorized}
    end
  end

  def delete_comment(_comment, _user), do: {:error, :unauthorized}

  defp create_revision(%Spec{} = spec, %User{} = user) do
    %Revision{}
    |> Revision.changeset(%{
      revision: spec.lock_version,
      title: spec.title,
      body: spec.body,
      status: spec.status,
      spec_id: spec.id,
      user_id: user.id
    })
    |> Repo.insert()
  end

  defp spec_topic(id), do: "#{@topic_prefix}:#{id}"

  defp preload_for_form(%Spec{} = spec), do: Repo.preload(spec, [:domains, :project])

  defp maybe_put_existing_domain_ids(changeset, attrs) do
    if domain_ids_present?(attrs) do
      changeset
    else
      domains = get_field_or_loaded_assoc(changeset.data, :domains)
      Changeset.put_change(changeset, :domain_ids, Enum.map(domains, & &1.id))
    end
  end

  defp get_field_or_loaded_assoc(spec, assoc) do
    case Map.fetch!(spec, assoc) do
      %Ecto.Association.NotLoaded{} -> []
      values -> values
    end
  end

  defp put_domains(%Spec{} = spec, attrs) do
    cond do
      domain_ids_present?(attrs) ->
        put_domain_ids(spec, normalized_domain_ids(attrs), attrs)

      project_id_present?(attrs) ->
        put_domain_ids(spec, existing_domain_ids_for_project(spec), attrs)

      true ->
        {:ok, spec}
    end
  end

  defp put_domain_ids(%Spec{} = spec, domain_ids, attrs) do
    domains =
      Repo.all(
        from(domain in Domain,
          join: project_domain in ProjectDomain,
          on: project_domain.domain_id == domain.id,
          where:
            domain.id in ^domain_ids and
              project_domain.project_id == ^spec.project_id
        )
      )

    if length(domains) == length(domain_ids) do
      spec
      |> Repo.preload(:domains)
      |> Changeset.change()
      |> Changeset.put_assoc(:domains, domains)
      |> Repo.update()
    else
      {:error,
       spec
       |> Spec.changeset(attrs)
       |> Changeset.add_error(:domain_ids, "contains unknown domains")}
    end
  end

  defp existing_domain_ids_for_project(%Spec{} = spec) do
    existing_domain_ids =
      spec
      |> Repo.preload(:domains)
      |> Map.fetch!(:domains)
      |> Enum.map(& &1.id)

    ProjectDomain
    |> where(
      [project_domain],
      project_domain.project_id == ^spec.project_id and
        project_domain.domain_id in ^existing_domain_ids
    )
    |> select([project_domain], project_domain.domain_id)
    |> Repo.all()
  end

  defp domain_ids_present?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, "domain_ids") or Map.has_key?(attrs, :domain_ids)
  end

  defp domain_ids_present?(_attrs), do: false

  defp normalized_domain_ids(attrs) do
    attrs
    |> Map.get("domain_ids", Map.get(attrs, :domain_ids, []))
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp record_spec_event(action, %Spec{} = spec, %User{} = user) do
    Audit.record(action, %{
      actor: user,
      target_type: "spec",
      target_id: spec.id,
      target_label: spec.title,
      metadata: %{
        "number" => spec.number && to_string(spec.number),
        "status" => spec.status && Atom.to_string(spec.status)
      }
    })
  end
end
