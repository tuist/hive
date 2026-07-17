defmodule Hive.Flights.Policy.Checks do
  @moduledoc false

  alias Hive.Auth

  def org_member(subject, _object), do: Auth.member?(subject)
end
