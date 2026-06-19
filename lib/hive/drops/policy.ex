defmodule Hive.Drops.Policy do
  @moduledoc """
  Authorization rules for reading drops.

  The subject is the current user (or `nil` for an anonymous viewer)
  and the object is a `Hive.Drops.Drop` (or the meadow it belongs to).
  Drops are read-only from the dashboard; source management is gated
  by `Hive.Ops.Policy` instead.

  - **read** — anyone can read drops from public meadows; members can
    read drops from every meadow.
  """

  use LetMe.Policy

  object :drop do
    action :read do
      allow(:public_meadow)
      allow(:org_member)
    end
  end
end
