defmodule Hive.Audit.Policy do
  @moduledoc """
  Authorization rules for the audit trail, expressed with LetMe.

  The subject is the current user (or `nil` for an anonymous visitor)
  and the object is the audit activity surface. Checks live in
  `Hive.Audit.Policy.Checks`.

  - **read** — restricted to users with the stored `:admin` role.
  """

  use LetMe.Policy

  object :audit_activity do
    action :read do
      allow(:admin)
    end
  end
end
