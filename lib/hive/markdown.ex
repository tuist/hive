defmodule Hive.Markdown do
  @moduledoc """
  Converts markdown bodies from signal sources into HTML for display.
  """

  @options [
    extension: [
      autolink: true,
      strikethrough: true,
      table: true,
      tagfilter: true,
      tasklist: true,
      underline: true
    ],
    parse: [
      relaxed_autolinks: true,
      relaxed_tasklist_matching: true,
      smart: true
    ],
    render: [unsafe: false]
  ]

  def to_html(nil), do: {:ok, ""}
  def to_html(""), do: {:ok, ""}

  def to_html(markdown) when is_binary(markdown) do
    MDEx.to_html(markdown, @options)
  end

  def to_html!(_markdown = nil), do: ""
  def to_html!(""), do: ""

  def to_html!(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown, @options)
  end
end
