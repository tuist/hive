defmodule Hive.Alerts.Policy do
  @moduledoc """
  Authorization rules for the alerting surface.

  Anyone who can see a project can see its alert rules; only admins can
  create, update, or delete them, because a misconfigured rule can send
  unwanted messages to a shared Slack channel and disrupt a workspace.
  """

  use LetMe.Policy

  object :alert_rule do
    action :read do
      allow(:member)
    end

    action :create do
      allow(:admin)
    end

    action :update do
      allow(:admin)
    end

    action :delete do
      allow(:admin)
    end
  end
end
