defmodule Hive.Forage.Policy.Checks do
  @moduledoc """
  Checks referenced by `Hive.Forage.Policy`. Each takes the subject (the
  current user, or `nil`) and the object (a forage source) and returns a
  boolean.
  """

  alias Hive.Auth

  def public_source(_subject, %{visibility: visibility}), do: visibility == :public
  def public_source(_subject, _object), do: false

  def creatable_source(_subject, %{creatable?: creatable?}), do: creatable? == true
  def creatable_source(_subject, _object), do: false

  def org_member(subject, _object), do: Auth.member?(subject)

  def authenticated(subject, _object), do: not is_nil(subject)
end
