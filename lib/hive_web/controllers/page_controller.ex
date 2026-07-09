defmodule HiveWeb.PageController do
  use HiveWeb, :controller

  alias Hive.Slack.Unfurl.BlockKit
  alias HiveWeb.AuditLive
  alias HiveWeb.ForageLive
  alias HiveWeb.OpsLive

  def slack_unfurl(uri, _params) do
    case uri.path do
      "/" ->
        BlockKit.open_graph(uri, ForageLive.Index.open_graph(%{total: 0, open: 0, domains: 0}))

      "/ops" ->
        BlockKit.open_graph(uri, OpsLive.Slack.open_graph())

      "/audit" ->
        BlockKit.open_graph(uri, AuditLive.open_graph())

      _path ->
        :skip
    end
  end

  def home(conn, _params) do
    redirect(conn, to: ~p"/forage")
  end

  def ops(conn, _params) do
    redirect(conn, to: ~p"/ops/slack")
  end

  def audit(conn, _params) do
    redirect(conn, to: ~p"/ops/audit")
  end
end
