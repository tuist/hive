defmodule Hive.Specs.ReviewRequests do
  @moduledoc """
  Builds the content used when a spec author asks for another review.
  """

  import Ecto.Query

  require Logger

  alias Hive.Agents
  alias Hive.Agents.Sessions
  alias Hive.Accounts.User
  alias Hive.Repo
  alias Hive.Specs.Agents.ReviewRequestAgent
  alias Hive.Specs.Revision
  alias Hive.Specs.Spec

  @max_body_length 8_000
  @max_summary_length 700
  @max_focus_items 3

  def draft(%Spec{} = spec, %User{} = requester, opts \\ []) do
    payload = fallback_payload(spec, requester)

    if agents_enabled?(opts) do
      runner = Keyword.get(opts, :runner, &run_agent(&1, opts))

      spec
      |> build_input(requester)
      |> runner.()
      |> handle_agent_result(payload)
    else
      {:ok, payload}
    end
  end

  def build_input(%Spec{} = spec, %User{} = requester) do
    revision = latest_revision(spec)

    %{
      spec: %{
        title: spec.title,
        status: status(spec.status),
        body: truncate(spec.body),
        summary: spec.summary || ""
      },
      last_revision: %{
        revision: revision_number(revision, spec),
        title: revision_title(revision, spec),
        status: revision_status(revision, spec),
        summary: revision_summary(revision)
      },
      requester: user_input(requester),
      commenters: Enum.map(reviewers(spec, requester), &user_input/1)
    }
  end

  def reviewers(%Spec{} = spec, %User{} = requester) do
    spec
    |> comments()
    |> Enum.map(& &1.user)
    |> Enum.filter(&match?(%User{}, &1))
    |> Enum.reject(&(&1.id == requester.id))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(&user_sort_key/1)
  end

  def reviewers(_spec, _requester), do: []

  defp handle_agent_result({:ok, %{summary: summary, review_focus: review_focus}}, payload) do
    {:ok, merge_agent_payload(payload, summary, review_focus)}
  end

  defp handle_agent_result(
         {:ok, %{"summary" => summary, "review_focus" => review_focus}},
         payload
       ) do
    {:ok, merge_agent_payload(payload, summary, review_focus)}
  end

  defp handle_agent_result({:ok, _other}, payload) do
    Logger.warning("[Specs.ReviewRequests] Agent returned an invalid review request payload")
    {:ok, payload}
  end

  defp handle_agent_result({:error, :llm_not_configured}, payload), do: {:ok, payload}

  defp handle_agent_result({:error, reason}, payload) do
    Logger.warning("[Specs.ReviewRequests] Agent failed: #{inspect(reason)}")
    {:ok, payload}
  end

  defp merge_agent_payload(payload, summary, review_focus) do
    summary = normalize_text(summary, @max_summary_length)

    review_focus =
      review_focus
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&normalize_text(&1, 180))
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(@max_focus_items)

    payload
    |> maybe_put_summary(summary)
    |> maybe_put_review_focus(review_focus)
  end

  defp maybe_put_summary(payload, ""), do: payload
  defp maybe_put_summary(payload, summary), do: Map.put(payload, :summary, summary)

  defp maybe_put_review_focus(payload, []), do: payload

  defp maybe_put_review_focus(payload, review_focus),
    do: Map.put(payload, :review_focus, review_focus)

  defp fallback_payload(%Spec{} = spec, %User{} = requester) do
    revision = latest_revision(spec)

    %{
      summary: fallback_summary(spec, revision),
      review_focus: fallback_review_focus(spec, revision),
      reviewers: reviewers(spec, requester),
      last_revision: revision
    }
  end

  defp fallback_summary(%Spec{summary: summary}, _revision)
       when is_binary(summary) and summary != "" do
    normalize_text(summary, @max_summary_length)
  end

  defp fallback_summary(_spec, %Revision{summary: summary})
       when is_binary(summary) and summary != "" do
    normalize_text(summary, @max_summary_length)
  end

  defp fallback_summary(%Spec{body: body}, _revision) do
    body
    |> normalize_text(@max_summary_length)
    |> case do
      "" -> "The latest revision is ready for another review."
      text -> text
    end
  end

  defp fallback_review_focus(_spec, %Revision{summary: summary})
       when is_binary(summary) and summary != "" do
    ["Check whether the latest revision resolves the changes described in the revision summary."]
  end

  defp fallback_review_focus(%Spec{status: :approved}, _revision) do
    ["Check whether the approved proposal is still ready to move into implementation."]
  end

  defp fallback_review_focus(%Spec{status: :in_progress}, _revision) do
    ["Check whether the proposal still matches the work currently in progress."]
  end

  defp fallback_review_focus(_spec, _revision) do
    ["Review the current proposal, tradeoffs, and acceptance criteria."]
  end

  defp latest_revision(%Spec{revisions: revisions}) when is_list(revisions) do
    Enum.max_by(revisions, & &1.revision, fn -> nil end)
  end

  defp latest_revision(%Spec{id: spec_id}) when is_binary(spec_id) do
    Revision
    |> where([revision], revision.spec_id == ^spec_id)
    |> order_by([revision], desc: revision.revision)
    |> limit(1)
    |> Repo.one()
  end

  defp latest_revision(_spec), do: nil

  defp comments(%Spec{comments: comments}) when is_list(comments), do: comments
  defp comments(_spec), do: []

  defp user_input(%User{} = user) do
    %{
      email: user.email || "",
      name: user.name || ""
    }
  end

  defp user_sort_key(%User{name: name, email: email}) do
    key =
      case normalize_text(name, 160) do
        "" -> email || ""
        name -> name
      end

    String.downcase(key)
  end

  defp revision_title(%Revision{title: title}, _spec), do: title
  defp revision_title(_revision, %Spec{title: title}), do: title

  defp revision_number(%Revision{revision: revision}, _spec), do: revision
  defp revision_number(_revision, %Spec{lock_version: lock_version}), do: lock_version

  defp revision_status(%Revision{status: status}, _spec), do: status(status)
  defp revision_status(_revision, %Spec{status: status}), do: status(status)

  defp revision_summary(%Revision{summary: summary}) when is_binary(summary), do: summary
  defp revision_summary(_revision), do: ""

  defp status(status) when is_atom(status), do: Atom.to_string(status)
  defp status(status), do: to_string(status)

  defp truncate(value) when is_binary(value) do
    if String.length(value) > @max_body_length,
      do: String.slice(value, 0, @max_body_length) <> "...",
      else: value
  end

  defp truncate(_value), do: ""

  defp normalize_text(value, max) when is_binary(value) do
    value
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, max)
  end

  defp normalize_text(_value, _max), do: ""

  defp run_agent(input, opts) do
    agent = Keyword.get(opts, :agent, ReviewRequestAgent)
    agent_opts = Keyword.get(opts, :agent_opts, [])

    Sessions.run_operation(agent, :draft_review_request, input, agent_opts)
  end

  defp agents_enabled?(opts) do
    fun = Keyword.get(opts, :agents_enabled?, &Agents.enabled?/0)
    fun.()
  end
end
