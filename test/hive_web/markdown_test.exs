defmodule HiveWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias HiveWeb.Markdown

  test "renders safe HTTP links" do
    html =
      "[Hive](https://hive.tuist.dev/specs/1)"
      |> Markdown.render()
      |> Phoenix.HTML.safe_to_string()

    assert html ==
             ~s(<p><a href="https://hive.tuist.dev/specs/1" rel="noopener noreferrer" target="_blank">Hive</a></p>)
  end

  test "does not render links with quoted URLs" do
    html =
      ~S|[Hive](https://hive.tuist.dev" onclick="alert(1))|
      |> Markdown.render()
      |> Phoenix.HTML.safe_to_string()

    refute html =~ "<a "
    refute html =~ ~s(onclick=")
    assert html =~ "&quot; onclick=&quot;alert(1)"
  end
end
