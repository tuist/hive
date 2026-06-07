defmodule Hive.Specs do
  @moduledoc """
  Editable product proposals that can be shaped from forage.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Hive.Accounts.User
  alias Hive.Auth
  alias Hive.Repo
  alias Hive.Specs.Comment
  alias Hive.Specs.Revision
  alias Hive.Specs.Spec

  def can_create?(user), do: Auth.member?(user)
  def can_edit?(_spec, user), do: Auth.member?(user)
  def can_comment?(_spec, %User{}), do: true
  def can_comment?(_spec, _user), do: false

  def list_specs(opts \\ []) do
    status = Keyword.get(opts, :status)

    Spec
    |> maybe_filter_by_status(status)
    |> order_by([spec], desc: spec.updated_at)
    |> preload([:source_feature_request, :created_by_user, :updated_by_user])
    |> Repo.all()
  end

  defp maybe_filter_by_status(query, nil), do: query

  defp maybe_filter_by_status(query, {:not, status})
       when status in [:draft, :proposed, :accepted, :in_progress, :shipped, :archived] do
    where(query, [spec], spec.status != ^status)
  end

  defp maybe_filter_by_status(query, status)
       when status in [:draft, :proposed, :accepted, :in_progress, :shipped, :archived] do
    where(query, [spec], spec.status == ^status)
  end

  defp maybe_filter_by_status(query, _status), do: query

  def get_spec!(id) do
    comments_query =
      from(comment in Comment, order_by: [asc: comment.inserted_at], preload: [user: :identities])

    revisions_query =
      from(revision in Revision,
        order_by: [desc: revision.revision],
        preload: [user: :identities]
      )

    Spec
    |> preload([
      :source_feature_request,
      :created_by_user,
      :updated_by_user,
      comments: ^comments_query,
      revisions: ^revisions_query
    ])
    |> Repo.get!(id)
  end

  def change_spec(spec \\ %Spec{}, attrs \\ %{}) do
    Spec.changeset(spec, attrs)
  end

  def create_spec(attrs, %User{} = user) do
    if can_create?(user) do
      Repo.transaction(fn ->
        with {:ok, spec} <-
               %Spec{}
               |> Spec.changeset(attrs)
               |> Changeset.put_change(:created_by_user_id, user.id)
               |> Changeset.put_change(:updated_by_user_id, user.id)
               |> Repo.insert(),
             {:ok, _revision} <- create_revision(spec, user) do
          spec
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      {:error, :unauthorized}
    end
  end

  def create_spec(_attrs, _user), do: {:error, :unauthorized}

  def update_spec(%Spec{} = spec, attrs, %User{} = user) do
    if can_edit?(spec, user) do
      Repo.transaction(fn ->
        with {:ok, spec} <-
               spec
               |> Spec.update_changeset(attrs)
               |> Changeset.put_change(:updated_by_user_id, user.id)
               |> Repo.update(stale_error_field: :lock_version),
             {:ok, _revision} <- create_revision(spec, user) do
          spec
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, spec} -> {:ok, spec}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :unauthorized}
    end
  end

  def update_spec(_spec, _attrs, _user), do: {:error, :unauthorized}

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
end
