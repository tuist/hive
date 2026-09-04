defmodule Hive.Alerts.Policy.Checks do
  @moduledoc """
  Checks referenced by `Hive.Alerts.Policy`.
  """

  alias Hive.Auth

  def member(subject, _object), do: Auth.member?(subject)
  def admin(subject, _object), do: Auth.admin?(subject)
end
