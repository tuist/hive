import "../css/app.css"

import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import Noora from "noora"
import MentionAutocomplete from "./hooks/mention_autocomplete"
import Clipboard from "./hooks/clipboard"
import { copyTextToClipboard } from "./clipboard"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")
const NooraSelect = {
  ...Noora.Hooks.NooraSelect,
  context() {
    const value = this.el.querySelector('[data-part="hidden-select"]')?.value

    return {
      ...Noora.Hooks.NooraSelect.context.call(this),
      defaultValue: value ? [value] : [],
    }
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { ...Noora.Hooks, NooraSelect, MentionAutocomplete, Clipboard },
})

liveSocket.connect()

window.liveSocket = liveSocket

window.addEventListener("phx:reset-form", (event) => {
  const form = document.getElementById(event.detail.id)
  if (form instanceof HTMLFormElement) form.reset()
})

window.addEventListener("phx:copy-to-clipboard", (event) => {
  const text = event.detail && event.detail.text
  if (typeof text !== "string" || text.length === 0) return
  copyTextToClipboard(text).catch((error) => {
    console.warn("Failed to copy text to clipboard", error)
  })
})

window.nooraChartFormatters = {
  ...(window.nooraChartFormatters || {}),
  firstAndLastDate: (el) => {
    let total = 0
    try {
      const raw = el.querySelector('[data-part="data"]')?.textContent
      const parsed = raw ? JSON.parse(raw) : null
      total = parsed?.xAxis?.data?.length || 0
    } catch (_) {
      total = 0
    }
    return (value, index) => {
      const first = index === 0
      const last = total > 0 && index === total - 1
      if (!first && !last) return ""
      const date = new Date(value)
      if (isNaN(date.getTime())) return String(value)
      return date.toLocaleDateString(navigator.language, {
        day: "numeric",
        month: "short",
      })
    }
  },
}
