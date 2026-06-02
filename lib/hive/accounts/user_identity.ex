defmodule Hive.Accounts.UserIdentity do
  @moduledoc """
  A single OAuth identity (a provider + that provider's stable user id)
  belonging to a `Hive.Accounts.User`. One user can accumulate several
  of these as they sign in through different providers.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Hive.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_identities" do
    field :provider, :string
    field :provider_uid, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_uid, :user_id])
    |> validate_required([:provider, :provider_uid, :user_id])
    |> unique_constraint([:provider, :provider_uid])
  end
end
