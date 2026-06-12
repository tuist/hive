defmodule Hive.Credo.Checks.RepoCallInEnum do
  @moduledoc """
  Flag direct `Repo.*` calls inside `Enum.*`, `Stream.*`, or `for`
  comprehensions. Classic N+1 shape: one DB round trip per iteration.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      `Repo.get/2`, `Repo.one/1`, `Repo.all/1`, `Repo.aggregate/3`,
      `Repo.exists?/1`, `Repo.preload/2,3`, and write calls inside `Enum.*`,
      `Stream.*`, or a `for` comprehension issue one DB round trip per
      iteration. Load the whole set with `where: r.id in ^ids` and group in
      Elixir, or use `Repo.insert_all/3` / `Repo.update_all/3` /
      `Repo.delete_all/2` for writes. `Repo.preload/2` already accepts a list
      and never needs to be mapped.

      Only direct calls on a module aliased as `Repo` are detected. Calls that
      reach `Repo` through a helper one hop away are out of static reach and
      belong to the PR-review skill.
      """
    ]

  @enumerator_funs %{
    Enum: ~w(map each flat_map filter reject reduce reduce_while find any? all? count_until)a,
    Stream: ~w(map each flat_map filter reject)a
  }

  @repo_funs ~w(
    get get! get_by get_by! one one! all aggregate exists? preload
    insert insert! update update! delete delete!
    insert_or_update insert_or_update!
  )a

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:for, meta, args} = ast, issues, issue_meta) when is_list(args) do
    case extract_do_block(args) do
      nil ->
        {ast, issues}

      body ->
        if repo_call_inside?(body) do
          {ast, issues ++ [issue_for("for comprehension", meta[:line], issue_meta)]}
        else
          {ast, issues}
        end
    end
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, mods}, fun]}, meta, args} = ast,
         issues,
         issue_meta
       )
       when is_list(args) and is_atom(fun) do
    mod = List.last(mods)

    if enumerator?(mod, fun) and Enum.any?(args, &repo_call_inside?/1) do
      {ast, issues ++ [issue_for("#{mod}.#{fun}", meta[:line], issue_meta)]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp enumerator?(mod, fun) do
    case Map.fetch(@enumerator_funs, mod) do
      {:ok, funs} -> fun in funs
      :error -> false
    end
  end

  defp extract_do_block(args) do
    case List.last(args) do
      kw when is_list(kw) -> Keyword.get(kw, :do)
      _ -> nil
    end
  end

  defp repo_call_inside?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        node, true ->
          {node, true}

        {{:., _, [{:__aliases__, _, mods}, fun]}, _, _} = node, _acc
        when is_atom(fun) ->
          if repo_call?(mods, fun), do: {node, true}, else: {node, false}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp repo_call?(mods, fun) do
    List.last(mods) == :Repo and fun in @repo_funs
  end

  defp issue_for(context, line_no, issue_meta) do
    format_issue(
      issue_meta,
      message:
        "Possible N+1: `Repo.*` call inside `#{context}`. Load with `where: r.id in ^ids` or use `*_all` for writes.",
      line_no: line_no
    )
  end
end
