defmodule Hive.Errors.Policy.Checks do
  @moduledoc """
  Checks referenced by `Hive.Errors.Policy`.
  """

  alias Hive.Auth

  def member(subject, _object), do: Auth.member?(subject)
  def admin(subject, _object), do: Auth.admin?(subject)
end
