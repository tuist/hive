import { copyTextToClipboard } from "../clipboard.js"

export default {
  mounted() {
    this.copyToClipboard = (event) => {
      const value = event.currentTarget.dataset.clipboardValue
      if (!value) return
      event.preventDefault()

      copyTextToClipboard(value, {
        container: this.el.closest("[role='dialog']"),
      }).catch((error) => {
        console.warn("Failed to copy text to clipboard", error)
      })
    }

    this.el.addEventListener("click", this.copyToClipboard)
  },

  destroyed() {
    if (this.copyToClipboard) {
      this.el.removeEventListener("click", this.copyToClipboard)
    }
  },
}
