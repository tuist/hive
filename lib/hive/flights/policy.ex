defmodule Hive.Flights.Policy do
  @moduledoc """
  Authorization rules for durable agent flights.
  """

  use LetMe.Policy

  object :flight do
    action :read do
      allow(:org_member)
    end

    action :create do
      allow(:org_member)
    end
  end
end
