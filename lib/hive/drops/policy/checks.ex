defmodule Hive.Drops.Policy.Checks do
  @moduledoc """
  Checks referenced by `Hive.Drops.Policy`. Each takes the subject
  (the current user, or `nil`) and the object (a `Hive.Drops.Drop` or
  the domain it belongs to) and returns a boolean.
  """

  alias Hive.Auth
  alias Hive.Drops.Drop
  alias Hive.Domains.Domain

  def public_domain(_subject, %Domain{visibility: :public}), do: true

  def public_domain(_subject, %Drop{domains: domains}) when is_list(domains),
    do: Enum.any?(domains, &(&1.visibility == :public))

  def public_domain(_subject, _object), do: false

  def org_member(subject, _object), do: Auth.member?(subject)
end
