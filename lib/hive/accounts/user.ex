defmodule Hive.Accounts.User do
  use Hive.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end

  def avatar_url(%__MODULE__{email: email}) do
    hash =
      email
      |> String.downcase()
      |> String.trim()
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)

    "https://gravatar.com/avatar/#{hash}?d=retro"
  end
end
