defmodule Hive.Drops.Policy.Checks do
  @moduledoc """
  Checks referenced by `Hive.Drops.Policy`. Each takes the subject
  (the current user, or `nil`) and the object (a `Hive.Drops.Drop` or
  the meadow it belongs to) and returns a boolean.
  """

  alias Hive.Auth
  alias Hive.Drops.Drop
  alias Hive.Meadows.Meadow

  def public_meadow(_subject, %Meadow{visibility: :public}), do: true

  def public_meadow(_subject, %Drop{meadows: meadows}) when is_list(meadows),
    do: Enum.any?(meadows, &(&1.visibility == :public))

  def public_meadow(_subject, _object), do: false

  def org_member(subject, _object), do: Auth.member?(subject)
end
