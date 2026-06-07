import "../css/app.css"

import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import Noora from "noora"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { ...Noora.Hooks },
})

liveSocket.connect()

window.liveSocket = liveSocket
