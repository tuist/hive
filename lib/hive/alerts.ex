defmodule Hive.Alerts do
  @moduledoc """
  Project-scoped alert rules and their delivery to configured
  destinations.

  A rule describes:

    * **when** to alert — a `trigger` on a supported `source` (v1 wires
      `:error_issue` with the `:new_issue_threshold` and `:regression`
      triggers)
    * **for which project** — every rule belongs to exactly one
      `Hive.Projects.Project`
    * **where** to send the alert — the destination fields (v1 wires
      Slack workspaces installed through Hive's Slack app)

  Two `tier` values, `:attention` and `:incident`, tag the urgency of a
  rule so destinations can render or route them differently (for Slack:
  a mention prefix like `<!here>` or `<!channel>`). They are otherwise
  the same delivery pipeline — nothing else in Hive is triggered off the
  tier.

  ## Evaluation

  `evaluate_error_issue/3` is called from the error ingest path after an
  issue has been created or bumped. It enqueues an Oban job per matching
  rule; the job re-checks the cooldown on the (rule, issue) pair inside
  the transaction that writes the notification row, so two concurrent
  events for the same issue can never send two Slack messages.
  """

  import Ecto.Query

  alias Hive.Alerts.Notification
  alias Hive.Alerts.Rule
  alias Hive.Alerts.Workers.DeliverRule
  alias Hive.Errors.Issue
  alias Hive.Projects.Project
  alias Hive.Repo

  ## Rule CRUD

  @doc "Lists rules for a project, newest first."
  def list_rules_for_project(%Project{id: project_id}), do: list_rules_for_project(project_id)

  def list_rules_for_project(project_id) when is_binary(project_id) do
    Rule
    |> where([rule], rule.project_id == ^project_id)
    |> order_by([rule], desc: rule.inserted_at)
    |> preload(:slack_installation)
    |> Repo.all()
  end

  def get_rule(id) when is_binary(id) do
    case Repo.get(Rule, id) do
      nil -> {:error, :not_found}
      %Rule{} = rule -> {:ok, Repo.preload(rule, [:project, :slack_installation])}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def change_rule(rule \\ %Rule{}, attrs \\ %{}), do: Rule.changeset(rule, attrs)

  def create_rule(%Project{id: project_id}, attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Map.put("project_id", project_id)
    |> then(&Rule.changeset(%Rule{}, &1))
    |> Repo.insert()
  end

  def update_rule(%Rule{} = rule, attrs) do
    rule
    |> Rule.changeset(attrs)
    |> Repo.update()
  end

  def delete_rule(%Rule{} = rule), do: Repo.delete(rule)

  ## Evaluation entry points

  @doc """
  Called from `Hive.Errors.record_event/2` after an issue has been
  created or bumped.

  `before` carries the pre-update state we need to tell a regression
  apart from a plain repeat: the caller sees the row `ensure_issue`
  returned (before the count/status bump) and the row
  `bump_issue_counters` returned (after). `context` carries per-event
  metadata rules can filter on (currently just `:environment`).
  """
  def evaluate_error_issue(%Issue{} = issue, %{} = before, %{} = context) do
    matching = matching_rules_for_issue(issue, before, context)

    Enum.each(matching, fn {rule, reason} ->
      %{
        "rule_id" => rule.id,
        "subject_type" => "error_issue",
        "subject_id" => issue.id,
        "reason" => Atom.to_string(reason),
        "environment" => Map.get(context, :environment)
      }
      |> DeliverRule.new()
      |> Oban.insert()
    end)

    :ok
  end

  @doc """
  Returns `[{rule, reason}]` for every enabled rule whose trigger
  fires on this event. Each rule appears at most once per event.
  """
  def matching_rules_for_issue(%Issue{} = issue, %{} = before, %{} = context) do
    Rule
    |> where([rule], rule.project_id == ^issue.project_id)
    |> where([rule], rule.enabled == true)
    |> where([rule], rule.source == :error_issue)
    |> Repo.all()
    |> Enum.filter(&rule_prefilters?(&1, issue, context))
    |> Enum.flat_map(fn rule ->
      case fire_reason(rule, issue, before) do
        nil -> []
        reason -> [{rule, reason}]
      end
    end)
  end

  defp rule_prefilters?(%Rule{} = rule, %Issue{} = issue, context) do
    level_matches?(rule, issue) and environment_matches?(rule, context)
  end

  defp level_matches?(%Rule{min_level: nil}, _issue), do: true

  defp level_matches?(%Rule{min_level: min}, %Issue{level: level}) do
    level_severity(level) >= level_severity(min)
  end

  defp level_severity(:fatal), do: 4
  defp level_severity(:error), do: 3
  defp level_severity(:warning), do: 2
  defp level_severity(:info), do: 1
  defp level_severity(:debug), do: 0
  defp level_severity(_other), do: 0

  defp environment_matches?(%Rule{environment: nil}, _context), do: true
  defp environment_matches?(%Rule{environment: ""}, _context), do: true

  defp environment_matches?(%Rule{environment: env}, %{environment: event_env}),
    do: env == event_env

  defp environment_matches?(_rule, _context), do: true

  # A regression is a resolved → unresolved transition on the same row.
  defp fire_reason(%Rule{trigger: :regression}, %Issue{status: :unresolved}, %{status: :resolved}),
       do: :regression

  defp fire_reason(%Rule{trigger: :regression}, _issue, _before), do: nil

  defp fire_reason(
         %Rule{trigger: :new_issue_threshold} = rule,
         %Issue{} = issue,
         _before
       ) do
    if issue.event_count >= rule.threshold_event_count and
         within_window?(issue.first_seen, rule.threshold_window_minutes) do
      :new_issue_threshold
    end
  end

  defp fire_reason(_rule, _issue, _before), do: nil

  defp within_window?(nil, _minutes), do: false

  defp within_window?(%DateTime{} = first_seen, minutes) when is_integer(minutes) do
    cutoff = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
    DateTime.compare(first_seen, cutoff) != :lt
  end

  ## Cooldown

  @doc """
  Returns the most recent `sent` notification for a (rule, subject),
  or `nil` if none.
  """
  def last_sent_notification(rule_id, subject_id)
      when is_binary(rule_id) and is_binary(subject_id) do
    Notification
    |> where([n], n.rule_id == ^rule_id)
    |> where([n], n.subject_id == ^subject_id)
    |> where([n], n.status == :sent)
    |> order_by([n], desc: n.fired_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  True when a rule already fired for this subject within its cooldown
  window. Used by the delivery worker to skip a redundant notification.
  """
  def in_cooldown?(%Rule{cooldown_minutes: minutes} = rule, subject_id)
      when is_integer(minutes) and is_binary(subject_id) do
    if minutes <= 0 do
      false
    else
      case last_sent_notification(rule.id, subject_id) do
        nil ->
          false

        %Notification{fired_at: at} ->
          cutoff = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
          DateTime.compare(at, cutoff) == :gt
      end
    end
  end

  def in_cooldown?(_rule, _subject_id), do: false

  @doc "Records a delivered/failed/skipped notification for the audit trail."
  def record_notification(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put_new("fired_at", DateTime.utc_now())

    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end
end
