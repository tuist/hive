defmodule HiveWeb.PlatformIcon do
  @moduledoc """
  Renders a small colored badge for a Sentry Software Development Kit
  `platform` identifier — an "E" on Elixir purple, "JS" on JavaScript
  yellow, and so on. Falls back to a neutral chip with the first two
  characters for unknown platforms so any SDK-supplied identifier
  renders cleanly.

  The color palette mirrors the widely recognised brand colors used by
  GitHub's language chips and the language pages on wikipedia — enough
  visual differentiation that the badge doubles as a language cue at a
  glance.
  """

  use Phoenix.Component

  attr :platform, :string, default: nil, doc: "SDK platform identifier such as 'elixir' or 'javascript'."
  attr :size, :string, default: "medium", values: ~w(small medium)
  attr :label, :boolean, default: false, doc: "Whether to render the friendly language name next to the badge."
  attr :rest, :global

  def platform_icon(assigns) do
    {initials, background, foreground, friendly_name} = badge(assigns.platform)

    assigns =
      assigns
      |> assign(:initials, initials)
      |> assign(:background, background)
      |> assign(:foreground, foreground)
      |> assign(:friendly_name, friendly_name)

    ~H"""
    <span class="platform-icon" data-size={@size} title={@friendly_name} {@rest}>
      <span
        data-part="badge"
        style={"background: #{@background}; color: #{@foreground};"}
        aria-hidden="true"
      >
        {@initials}
      </span>
      <span :if={@label} data-part="label">{@friendly_name}</span>
    </span>
    """
  end

  # {initials, background, foreground, friendly label}
  defp badge("elixir"), do: {"E", "#4B275F", "#FFFFFF", "Elixir"}
  defp badge("erlang"), do: {"ER", "#A90533", "#FFFFFF", "Erlang"}
  defp badge("javascript"), do: {"JS", "#F7DF1E", "#000000", "JavaScript"}
  defp badge("node"), do: {"N", "#5FA04E", "#FFFFFF", "Node.js"}
  defp badge("node.js"), do: {"N", "#5FA04E", "#FFFFFF", "Node.js"}
  defp badge("typescript"), do: {"TS", "#3178C6", "#FFFFFF", "TypeScript"}
  defp badge("python"), do: {"Py", "#3776AB", "#FFD343", "Python"}
  defp badge("ruby"), do: {"R", "#CC342D", "#FFFFFF", "Ruby"}
  defp badge("go"), do: {"Go", "#00ADD8", "#FFFFFF", "Go"}
  defp badge("java"), do: {"J", "#F89820", "#FFFFFF", "Java"}
  defp badge("csharp"), do: {"C#", "#512BD4", "#FFFFFF", "C#"}
  defp badge("php"), do: {"P", "#777BB4", "#FFFFFF", "PHP"}
  defp badge("perl"), do: {"Pl", "#39457E", "#FFFFFF", "Perl"}
  defp badge("rust"), do: {"Rs", "#DEA584", "#000000", "Rust"}
  defp badge("swift"), do: {"S", "#F05138", "#FFFFFF", "Swift"}
  defp badge("cocoa"), do: {"", "#000000", "#FFFFFF", "Cocoa"}
  defp badge("objc"), do: {"OC", "#438EFF", "#FFFFFF", "Objective-C"}
  defp badge("kotlin"), do: {"K", "#A97BFF", "#000000", "Kotlin"}
  defp badge("dart"), do: {"D", "#0175C2", "#13B9FD", "Dart"}
  defp badge("flutter"), do: {"F", "#02569B", "#54C5F8", "Flutter"}
  defp badge("android"), do: {"A", "#3DDC84", "#000000", "Android"}
  defp badge("native"), do: {"C", "#00599C", "#FFFFFF", "Native"}
  defp badge("c"), do: {"C", "#A8B9CC", "#000000", "C"}
  defp badge("cpp"), do: {"C+", "#00599C", "#FFFFFF", "C++"}
  defp badge("scala"), do: {"Sc", "#DC322F", "#FFFFFF", "Scala"}
  defp badge("haskell"), do: {"H", "#5D4F85", "#FFFFFF", "Haskell"}
  defp badge("clojure"), do: {"Cj", "#5881D8", "#FFFFFF", "Clojure"}
  defp badge("other"), do: {"?", "#8B8D97", "#FFFFFF", "Other"}
  defp badge(nil), do: {"?", "#8B8D97", "#FFFFFF", "Unknown"}
  defp badge(""), do: {"?", "#8B8D97", "#FFFFFF", "Unknown"}

  defp badge(name) when is_binary(name) do
    initials = name |> String.slice(0, 2) |> String.upcase()
    label = String.capitalize(name)
    {initials, "#8B8D97", "#FFFFFF", label}
  end
end
