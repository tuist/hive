defmodule Hive.Audit.Policy.Checks do
  @moduledoc """
  Checks referenced by `Hive.Audit.Policy`. Each takes the subject (the
  current user, or `nil`) and the object (unused here) and returns a
  boolean.
  """

  alias Hive.Auth

  def admin(subject, _object), do: Auth.admin?(subject)
end
