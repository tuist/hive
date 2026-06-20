defmodule Hive.Drops.Policy do
  @moduledoc """
  Authorization rules for reading drops.

  The subject is the current user (or `nil` for an anonymous viewer)
  and the object is a `Hive.Drops.Drop` (or the domain it belongs to).
  Drops are read-only from the dashboard; source management is gated
  by `Hive.Ops.Policy` instead.

  - **read** — anyone can read drops from public domains; members can
    read drops from every domain.
  """

  use LetMe.Policy

  object :drop do
    action :read do
      allow(:public_domain)
      allow(:org_member)
    end
  end
end
