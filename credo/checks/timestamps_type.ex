defmodule Hive.Credo.Checks.TimestampsType do
  @moduledoc """
  Ensure that `timestamps(...)` calls declare an explicit type. Defaults are
  reserved for backward compatibility and almost never what the project wants.
  Configured per scope: `:utc_datetime` (or `:utc_datetime_usec`) in schemas,
  `:timestamptz` in migrations.
  """

  use Credo.Check,
    param_defaults: [allowed_type: :utc_datetime],
    category: :warning,
    explanations: [
      check: """
      Ecto's `timestamps/1` macro should specify an explicit type. Migrations
      should use a timezone-aware type (`:timestamptz`); schemas should use
      `:utc_datetime` or `:utc_datetime_usec`. The bare default
      (`:naive_datetime`) drops timezone information and is a foot-gun for
      cross-region deployments.
      """,
      params: [allowed_type: "The type required for `timestamps(type: ...)`"]
    ]

  def run(source_file, params \\ []) do
    allowed_type = Params.get(params, :allowed_type, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, allowed_type, issue_meta))
  end

  defp traverse({:timestamps, meta, [opts]} = ast, issues, allowed_type, issue_meta)
       when is_list(opts) do
    if Keyword.get(opts, :type) == allowed_type do
      {ast, issues}
    else
      {ast, issues ++ [issue_for(allowed_type, meta[:line], issue_meta)]}
    end
  end

  defp traverse({:timestamps, meta, []} = ast, issues, allowed_type, issue_meta) do
    {ast, issues ++ [issue_for(allowed_type, meta[:line], issue_meta)]}
  end

  defp traverse({:timestamps, meta, nil} = ast, issues, allowed_type, issue_meta) do
    {ast, issues ++ [issue_for(allowed_type, meta[:line], issue_meta)]}
  end

  defp traverse(ast, issues, _allowed_type, _issue_meta), do: {ast, issues}

  defp issue_for(allowed_type, line_no, issue_meta) do
    format_issue(
      issue_meta,
      message: "`timestamps/1` should specify `type: #{inspect(allowed_type)}`.",
      line_no: line_no
    )
  end
end
