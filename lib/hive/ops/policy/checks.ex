defmodule Hive.Ops.Policy.Checks do
  @moduledoc """
  Checks referenced by `Hive.Ops.Policy`.
  """

  alias Hive.Auth

  def admin(subject, _object), do: Auth.admin?(subject)
end
