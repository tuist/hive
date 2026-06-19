defmodule Hive.Ops.Policy do
  @moduledoc """
  Authorization rules for operational administration surfaces.

  The subject is the current user (or `nil` for an anonymous visitor)
  and the object is the operational surface being managed. Checks live
  in `Hive.Ops.Policy.Checks`.

  - **manage Slack workspaces** — restricted to users with the stored
    `:admin` role.
  - **manage drop sources** — restricted to users with the stored
    `:admin` role.
  """

  use LetMe.Policy

  object :slack_workspace do
    action :manage do
      allow(:admin)
    end
  end

  object :drop_source do
    action :manage do
      allow(:admin)
    end
  end
end
