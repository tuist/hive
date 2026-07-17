defmodule Hive.Forage.Policy do
  @moduledoc """
  Authorization rules for forage sources, expressed with LetMe.

  The subject is the current user (or `nil` for an anonymous visitor) and
  the object is the relevant forage resource. Checks live in
  `Hive.Forage.Policy.Checks`.

  - **read** — public sources are open to everyone; organization sources
    are restricted to org members.
  - **create** — only creatable sources, and only for someone allowed to
    act on them: any authenticated user for public sources, members for
    organization sources.
  """

  use LetMe.Policy

  object :forage_source do
    action :read do
      allow(:public_source)
      allow(:org_member)
    end

    action :create do
      allow([:creatable_source, :public_source, :authenticated])
      allow([:creatable_source, :org_member])
    end
  end
end
