import "../css/app.css"

import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import Noora from "noora"
import MentionAutocomplete from "./hooks/mention_autocomplete"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { ...Noora.Hooks, MentionAutocomplete },
})

liveSocket.connect()

window.liveSocket = liveSocket

window.addEventListener("phx:reset-form", (event) => {
  const form = document.getElementById(event.detail.id)
  if (form instanceof HTMLFormElement) form.reset()
})
