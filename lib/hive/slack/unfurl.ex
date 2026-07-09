defmodule Hive.Slack.Unfurl do
  @moduledoc """
  Behaviour for turning a Hive URL into a Slack unfurl payload.

  Dashboard route modules can implement this behaviour when the route
  needs to fetch route-specific data before deciding what Slack may see.
  Routes that can use static metadata can expose `open_graph/0` instead,
  and `Hive.Slack.Unfurler` will convert it to a Slack Block Kit payload.

  The payload follows Slack's `chat.unfurl` Block Kit shape:

      %{
        "blocks" => [...]
      }

  Implementations should return `:skip` when:

    * the URL isn't theirs (path doesn't match)
    * the resource exists but isn't safe to expose to the workspace
      (e.g. private spec, organization-only forage item, or Hive itself
      running in private mode)
    * the resource can't be found
  """

  @type payload :: %{optional(String.t()) => term()}

  @callback slack_unfurl(URI.t(), map()) :: {:ok, payload} | :skip
end
