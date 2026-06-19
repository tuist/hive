defmodule Hive.Forage.Item do
  @moduledoc """
  Unified read model for work-like signals that appear in Forage.

  Manual submissions, GitHub issues, and Grafana alerts keep their
  source-specific persistence, then project into this shape for list,
  feed, and agent inputs.
  """

  @enforce_keys [:id, :type, :title, :status, :updated_at]
  defstruct [
    :id,
    :type,
    :origin,
    :source_record_id,
    :title,
    :body,
    :status,
    :visibility,
    :source_label,
    :external_label,
    :external_url,
    :repository_id,
    :requester_label,
    :occurred_at,
    :updated_at,
    :source_record,
    :comments,
    :comments_status,
    :comments_error,
    domains: []
  ]
end
