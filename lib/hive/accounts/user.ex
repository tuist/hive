defmodule Hive.Accounts.User do
  @moduledoc """
  A person who has authenticated with the instance, identified by email.

  A user may sign in through several providers; each of those is a
  `Hive.Accounts.UserIdentity` linked back here. Hive is single-tenant:
  the deployment *is* the organization, and a user's role (member vs
  external contributor) is derived from their email domain rather than
  stored. See `Hive.Auth.role/1`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.UserIdentity

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string

    has_many :identities, UserIdentity

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email])
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
  end

  def normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  def normalize_email(email), do: email
end
