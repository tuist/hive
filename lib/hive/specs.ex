defmodule Hive.Specs do
  @moduledoc """
  Editable meadow proposals that can be shaped from forage.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Hive.Accounts.User
  alias Hive.Audit
  alias Hive.Auth
  alias Hive.Meadows.Meadow
  alias Hive.Repo
  alias Hive.Specs.Comment
  alias Hive.Specs.Revision
  alias Hive.Specs.RevisionSummaryWorker
  alias Hive.Specs.Spec
  alias Hive.Specs.View

  @spec_number_lock_namespace 0x48695645
  @spec_number_lock_key 0x53504353

  def can_create?(user), do: Auth.member?(user)
  def can_edit?(_spec, user), do: Auth.member?(user)
  def can_comment?(spec, %User{} = user), do: can_view?(spec, user)
  def can_comment?(_spec, _user), do: false

  def can_edit_comment?(%Comment{user_id: user_id}, %User{id: user_id}) when is_binary(user_id),
    do: true

  def can_edit_comment?(_comment, _user), do: false

  def can_view?(%Spec{} = spec, user),
    do: Auth.member?(user) or effective_visibility(spec) == :public

  def effective_visibility(%Spec{visibility: visibility}) when visibility in [:public, :private],
    do: visibility

  def effective_visibility(%Spec{} = spec) do
    if has_private_meadow?(spec), do: :private, else: :public
  end

  def list_specs(opts \\ []) do
    status = Keyword.get(opts, :status)
    user = Keyword.get(opts, :user)

    specs =
      Spec
      |> maybe_filter_by_status(status)
      |> maybe_filter_by_visibility(user)
      |> order_by([spec], desc: spec.updated_at)
      |> preload([:source_feature_request, :created_by_user, :updated_by_user, :meadows])
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
      private_meadow_spec_ids =
        from(meadow in Meadow,
          join: meadow_spec in "meadows_specs",
          on: meadow_spec.meadow_id == meadow.id,
          where: meadow.visibility == :private,
          select: meadow_spec.spec_id
        )

      where(
        query,
        [spec],
        spec.visibility == :public or
          (is_nil(spec.visibility) and spec.id not in subquery(private_meadow_spec_ids))
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
      :source_feature_request,
      :created_by_user,
      :updated_by_user,
      :meadows,
      comments: ^comments_query,
      revisions: ^revisions_query
    ])
  end

  def change_spec(spec \\ %Spec{}, attrs \\ %{}) do
    spec
    |> preload_meadows()
    |> Spec.changeset(attrs)
    |> maybe_put_existing_meadow_ids(attrs)
  end

  def create_spec(attrs, %User{} = user) do
    if can_create?(user) do
      Repo.transaction(fn -> create_spec_transaction(attrs, user) end)
      |> case do
        {:ok, spec} ->
          record_spec_event("spec.created", spec, user)
          Hive.Meadows.schedule_evolution()
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
      Repo.transaction(fn -> update_spec_transaction(spec, attrs, user) end)
      |> case do
        {:ok, updated_spec} ->
          record_spec_event("spec.updated", updated_spec, user)
          Hive.Meadows.schedule_evolution()
          {:ok, updated_spec}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :unauthorized}
    end
  end

  def update_spec(_spec, _attrs, _user), do: {:error, :unauthorized}

  defp create_spec_transaction(attrs, user) do
    with {:ok, spec} <-
           %Spec{}
           |> Spec.changeset(attrs)
           |> Changeset.put_change(:created_by_user_id, user.id)
           |> Changeset.put_change(:updated_by_user_id, user.id)
           |> put_next_spec_number()
           |> Repo.insert(),
         {:ok, spec} <- put_meadows(spec, attrs),
         {:ok, _revision} <- create_revision(spec, user) do
      spec
    else
      {:error, reason} -> Repo.rollback(reason)
    end
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

  defp update_spec_transaction(spec, attrs, user) do
    with {:ok, spec} <-
           spec
           |> Spec.update_changeset(attrs)
           |> Changeset.put_change(:updated_by_user_id, user.id)
           |> Repo.update(stale_error_field: :lock_version),
         {:ok, spec} <- put_meadows(spec, attrs),
         {:ok, _revision} <- create_revision(spec, user) do
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
      %Comment{}
      |> Comment.changeset(attrs)
      |> Changeset.put_change(:spec_id, spec.id)
      |> Changeset.put_change(:user_id, user.id)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def add_comment(_spec, _attrs, _user), do: {:error, :unauthorized}

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

  defp create_revision(%Spec{} = spec, %User{} = user) do
    with {:ok, revision} <-
           %Revision{}
           |> Revision.changeset(%{
             revision: spec.lock_version,
             title: spec.title,
             body: spec.body,
             status: spec.status,
             spec_id: spec.id,
             user_id: user.id
           })
           |> Repo.insert() do
      schedule_revision_summary(revision)
      {:ok, revision}
    end
  end

  defp schedule_revision_summary(%Revision{revision: 1}), do: :skipped

  defp schedule_revision_summary(%Revision{id: id}) do
    RevisionSummaryWorker.enqueue(id)
  end

  defp preload_meadows(%Spec{} = spec), do: Repo.preload(spec, :meadows)

  defp maybe_put_existing_meadow_ids(changeset, attrs) do
    if meadow_ids_present?(attrs) do
      changeset
    else
      meadows = get_field_or_loaded_assoc(changeset.data, :meadows)
      Changeset.put_change(changeset, :meadow_ids, Enum.map(meadows, & &1.id))
    end
  end

  defp get_field_or_loaded_assoc(spec, assoc) do
    case Map.fetch!(spec, assoc) do
      %Ecto.Association.NotLoaded{} -> []
      values -> values
    end
  end

  defp has_private_meadow?(%Spec{meadows: %Ecto.Association.NotLoaded{}, id: id})
       when is_binary(id) do
    Repo.exists?(
      from(meadow in Meadow,
        join: meadow_spec in "meadows_specs",
        on: meadow_spec.meadow_id == meadow.id,
        where: meadow_spec.spec_id == ^id and meadow.visibility == :private
      )
    )
  end

  defp has_private_meadow?(%Spec{meadows: meadows}) when is_list(meadows) do
    Enum.any?(meadows, &(&1.visibility == :private))
  end

  defp has_private_meadow?(_spec), do: false

  defp put_meadows(%Spec{} = spec, attrs) do
    if meadow_ids_present?(attrs) do
      meadow_ids = normalized_meadow_ids(attrs)
      meadows = Repo.all(from(meadow in Meadow, where: meadow.id in ^meadow_ids))

      if length(meadows) == length(meadow_ids) do
        spec
        |> Repo.preload(:meadows)
        |> Changeset.change()
        |> Changeset.put_assoc(:meadows, meadows)
        |> Repo.update()
      else
        {:error,
         spec
         |> Spec.changeset(attrs)
         |> Changeset.add_error(:meadow_ids, "contains unknown meadows")}
      end
    else
      {:ok, spec}
    end
  end

  defp meadow_ids_present?(attrs) when is_map(attrs) do
    Map.has_key?(attrs, "meadow_ids") or Map.has_key?(attrs, :meadow_ids)
  end

  defp meadow_ids_present?(_attrs), do: false

  defp normalized_meadow_ids(attrs) do
    attrs
    |> Map.get("meadow_ids", Map.get(attrs, :meadow_ids, []))
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

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
