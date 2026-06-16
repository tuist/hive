defmodule Hive.Accounts.User do
  @moduledoc """
  A person who has authenticated with the instance, identified by email.

  A user may sign in through several providers; each of those is a
  `Hive.Accounts.UserIdentity` linked back here. Hive is single-tenant:
  the deployment *is* the organization.

  The stored `:role` field is the single source of truth for what the
  user can do, ordered weakest to strongest:

  - `:collaborator` — signed in, but not part of the org. The default
    for any user whose email domain is not in `HIVE_ORG_DOMAINS`.
  - `:member` — part of the org. The default for users whose email
    domain matches `HIVE_ORG_DOMAINS` at signup (or every signed-in
    user when no org domains are configured).
  - `:admin` — explicitly promoted; gates admin-only surfaces like
    the audit trail.

  The role is derived from the email domain at signup and then
  persisted, so changing `HIVE_ORG_DOMAINS` afterwards does not
  reclassify existing users. Promote and demote with
  `Hive.Accounts.update_user_role/2`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.UserIdentity

  @roles ~w(collaborator member admin)a

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: @roles, default: :collaborator

    has_many :identities, UserIdentity

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role])
    |> update_change(:email, &normalize_email/1)
    |> update_change(:name, &normalize_string/1)
    |> validate_required([:email])
    |> validate_length(:email, max: 160)
    |> validate_length(:name, max: 160)
    |> validate_inclusion(:role, @roles)
    |> unique_constraint(:email)
  end

  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
  end

  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  def normalize_email(email), do: email

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: value
end
