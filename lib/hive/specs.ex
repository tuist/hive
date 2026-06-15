defmodule Hive.Specs do
  @moduledoc """
  Editable meadow proposals that can be shaped from forage.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Hive.Accounts.User
  alias Hive.Auth
  alias Hive.Meadows.Meadow
  alias Hive.Repo
  alias Hive.Specs.Comment
  alias Hive.Specs.Revision
  alias Hive.Specs.Spec

  def can_create?(user), do: Auth.member?(user)
  def can_edit?(_spec, user), do: Auth.member?(user)
  def can_comment?(spec, %User{} = user), do: can_view?(spec, user)
  def can_comment?(_spec, _user), do: false

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

    Spec
    |> maybe_filter_by_status(status)
    |> maybe_filter_by_visibility(user)
    |> order_by([spec], desc: spec.updated_at)
    |> preload([:source_feature_request, :created_by_user, :updated_by_user, :meadows])
    |> Repo.all()
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
        {:ok, spec} ->
          Hive.Meadows.schedule_evolution()
          {:ok, spec}

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
           |> Repo.insert(),
         {:ok, spec} <- put_meadows(spec, attrs),
         {:ok, _revision} <- create_revision(spec, user) do
      spec
    else
      {:error, reason} -> Repo.rollback(reason)
    end
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

  def add_comment(%Spec{} = spec, attrs, user \\ nil) do
    if can_comment?(spec, user) do
      %Comment{}
      |> Comment.changeset(attrs)
      |> Changeset.put_change(:spec_id, spec.id)
      |> maybe_put_user(user)
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  defp maybe_put_user(changeset, %User{} = user),
    do: Changeset.put_change(changeset, :user_id, user.id)

  defp maybe_put_user(changeset, _user), do: changeset

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
end
