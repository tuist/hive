defmodule Hive.Slack.Unfurl do
  @moduledoc """
  Behaviour for turning a Hive URL into a Slack unfurl payload.

  Each domain that wants its URLs unfurled in Slack implements this
  behaviour and is registered in `Hive.Slack.Unfurler`. The dispatcher
  walks the registry and uses the first module that returns
  `{:ok, payload}` for a given URL.

  The payload follows Slack's `chat.unfurl` attachment shape:

      %{
        "title" => "Spec 42: Add Slack unfurling",
        "title_link" => "https://hive.tuist.dev/specs/42",
        "text" => "Short summary",
        "footer" => "Hive · spec · in_progress",
        "color" => "#1A1A1A",
        "blocks" => [...]            # optional, Block Kit
      }

  Implementations should return `:skip` when:

    * the URL isn't theirs (path doesn't match)
    * the resource exists but isn't safe to expose to the workspace
      (e.g. private spec, organization-only forage item, or Hive itself
      running in private mode)
    * the resource can't be found
  """

  @type payload :: %{optional(String.t()) => term()}

  @callback unfurl(URI.t()) :: {:ok, payload} | :skip
end
