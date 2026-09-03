defmodule Hive.Errors.Policy do
  @moduledoc """
  Authorization rules for the error tracking surface.

  Error events routinely carry sensitive data: user identifiers,
  request payloads, and stack-trace context that can include
  application internals. The dashboard and Model Context Protocol
  tools that read this data are therefore restricted to authenticated
  organization members, and anonymous requests receive a 404 rather
  than a redirect so route existence is not disclosed.

  The ingest endpoint (`POST /api/:project_id/envelope/`) is not
  covered by this policy: it authenticates by Data Source Name public
  key, not by a session, so it can be reached from any Software
  Development Kit that holds a valid key.
  """

  use LetMe.Policy

  object :error_issue do
    action :read do
      allow(:member)
    end

    action :resolve do
      allow(:member)
    end

    action :ignore do
      allow(:member)
    end
  end

  object :error_project_key do
    action :read do
      allow(:member)
    end

    action :create do
      allow(:admin)
    end
  end
end
