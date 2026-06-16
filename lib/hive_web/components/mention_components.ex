defmodule HiveWeb.MentionComponents do
  @moduledoc false

  use HiveWeb, :html

  alias Phoenix.HTML.FormField

  attr :id, :string, default: nil
  attr :field, FormField, required: true
  attr :mention_suggestions, :list, default: []
  attr :label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :max_length, :integer, default: 20_000
  attr :rows, :integer, default: 5
  attr :required, :boolean, default: false
  attr :show_required, :boolean, default: false
  attr :show_character_count, :boolean, default: true
  attr :resize, :string, default: "vertical"
  attr :rest, :global

  def mention_text_area(assigns) do
    assigns =
      assigns
      |> assign(:id, assigns.id || assigns.field.id)
      |> assign(:mention_suggestions_json, Jason.encode!(assigns.mention_suggestions))

    ~H"""
    <.text_area
      id={@id}
      field={@field}
      label={@label}
      placeholder={@placeholder}
      max_length={@max_length}
      rows={@rows}
      required={@required}
      show_required={@show_required}
      show_character_count={@show_character_count}
      resize={@resize}
      phx-hook="MentionAutocomplete"
      data-mention-suggestions={@mention_suggestions_json}
      {@rest}
    />
    """
  end
end
