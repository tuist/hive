const MAX_VISIBLE_SUGGESTIONS = 6
const MENTION_QUERY = /(^|[^A-Za-z0-9_/])@([A-Za-z0-9._-]*)$/
const CARET_MIRROR_STYLES = [
  "boxSizing",
  "width",
  "borderTopWidth",
  "borderRightWidth",
  "borderBottomWidth",
  "borderLeftWidth",
  "paddingTop",
  "paddingRight",
  "paddingBottom",
  "paddingLeft",
  "fontFamily",
  "fontSize",
  "fontStyle",
  "fontVariant",
  "fontWeight",
  "letterSpacing",
  "lineHeight",
  "textAlign",
  "textIndent",
  "textTransform",
  "wordSpacing",
  "tabSize",
]

const parseSuggestions = (element) => {
  try {
    return JSON.parse(element.dataset.mentionSuggestions || "[]").filter(
      (suggestion) => suggestion.token && (suggestion.name || suggestion.email)
    )
  } catch (_error) {
    return []
  }
}

const currentMention = (element) => {
  const cursor = element.selectionStart
  if (cursor === null || element.selectionEnd !== cursor) return null

  const beforeCursor = element.value.slice(0, cursor)
  const match = beforeCursor.match(MENTION_QUERY)
  if (!match) return null

  const query = match[2]

  return {
    start: cursor - query.length - 1,
    end: cursor,
    query: query.toLowerCase(),
  }
}

const matchingSuggestions = (suggestions, query) => {
  return suggestions
    .filter((suggestion) => {
      if (query === "") return true

      const token = suggestion.token || ""
      const name = suggestion.name || ""
      const email = suggestion.email || ""

      return (
        token.toLowerCase().startsWith(query) ||
        name.toLowerCase().includes(query) ||
        email.toLowerCase().includes(query)
      )
    })
    .slice(0, MAX_VISIBLE_SUGGESTIONS)
}

const parsedLineHeight = (style) => {
  const lineHeight = Number.parseFloat(style.lineHeight)
  if (!Number.isNaN(lineHeight)) return lineHeight

  const fontSize = Number.parseFloat(style.fontSize)
  return Number.isNaN(fontSize) ? 20 : fontSize * 1.2
}

const caretCoordinates = (element, position) => {
  const style = window.getComputedStyle(element)
  const mirror = document.createElement("div")

  CARET_MIRROR_STYLES.forEach((property) => {
    mirror.style[property] = style[property]
  })

  mirror.style.position = "absolute"
  mirror.style.visibility = "hidden"
  mirror.style.whiteSpace = "pre-wrap"
  mirror.style.overflowWrap = "break-word"
  mirror.style.top = "0"
  mirror.style.left = "-9999px"
  mirror.style.width = `${element.clientWidth}px`

  mirror.textContent = element.value.slice(0, position)

  const marker = document.createElement("span")
  marker.textContent = "\u200b"
  mirror.appendChild(marker)
  document.body.appendChild(mirror)

  const markerRect = marker.getBoundingClientRect()
  const mirrorRect = mirror.getBoundingClientRect()
  const coordinates = {
    left: markerRect.left - mirrorRect.left - element.scrollLeft,
    top: markerRect.top - mirrorRect.top - element.scrollTop + parsedLineHeight(style),
  }

  mirror.remove()

  return coordinates
}

const clamp = (value, minimum, maximum) => {
  return Math.min(Math.max(value, minimum), maximum)
}

const MentionAutocomplete = {
  mounted() {
    this.suggestions = parseSuggestions(this.el)
    this.matches = []
    this.activeIndex = 0
    this.range = null

    this.menu = document.createElement("div")
    this.menu.id = `${this.el.id}-mention-autocomplete`
    this.menu.dataset.part = "mention-autocomplete"
    this.menu.setAttribute("role", "listbox")
    this.menu.hidden = true

    this.el.parentElement.appendChild(this.menu)
    this.el.setAttribute("aria-controls", this.menu.id)
    this.el.setAttribute("aria-expanded", "false")

    this.handleInput = () => this.updateMenu()
    this.handleCursorChange = () => this.updateMenu()
    this.handleKeydown = (event) => this.onKeydown(event)
    this.handleBlur = () => setTimeout(() => this.closeMenu(), 100)
    this.handleScroll = () => this.positionMenu()
    this.handleResize = () => this.positionMenu()

    this.el.addEventListener("input", this.handleInput)
    this.el.addEventListener("click", this.handleCursorChange)
    this.el.addEventListener("keyup", this.handleCursorChange)
    this.el.addEventListener("keydown", this.handleKeydown)
    this.el.addEventListener("blur", this.handleBlur)
    this.el.addEventListener("scroll", this.handleScroll)
    window.addEventListener("resize", this.handleResize)
  },

  updated() {
    this.suggestions = parseSuggestions(this.el)
    this.ensureMenu()
    if (document.activeElement === this.el) this.updateMenu()
  },

  destroyed() {
    this.destroy()
  },

  destroy() {
    this.el.removeEventListener("input", this.handleInput)
    this.el.removeEventListener("click", this.handleCursorChange)
    this.el.removeEventListener("keyup", this.handleCursorChange)
    this.el.removeEventListener("keydown", this.handleKeydown)
    this.el.removeEventListener("blur", this.handleBlur)
    this.el.removeEventListener("scroll", this.handleScroll)
    window.removeEventListener("resize", this.handleResize)
    this.menu?.remove()
  },

  updateMenu() {
    if (document.activeElement !== this.el) {
      this.closeMenu()
      return
    }

    this.range = currentMention(this.el)

    if (!this.range) {
      this.closeMenu()
      return
    }

    this.matches = matchingSuggestions(this.suggestions, this.range.query)
    this.activeIndex = Math.min(this.activeIndex, Math.max(this.matches.length - 1, 0))

    if (this.matches.length === 0) {
      this.closeMenu()
      return
    }

    this.renderMenu()
    this.openMenu()
  },

  ensureMenu() {
    if (!this.menu.isConnected) {
      this.el.parentElement.appendChild(this.menu)
    }
  },

  renderMenu() {
    this.menu.replaceChildren()

    this.matches.forEach((suggestion, index) => {
      const item = document.createElement("button")
      item.id = `${this.menu.id}-option-${index}`
      item.type = "button"
      item.dataset.part = "mention-autocomplete-item"
      item.dataset.selected = index === this.activeIndex ? "true" : "false"
      item.setAttribute("role", "option")
      item.setAttribute("aria-selected", index === this.activeIndex ? "true" : "false")

      const name = document.createElement("span")
      name.dataset.part = "mention-autocomplete-name"
      name.textContent = suggestion.name || suggestion.email

      item.appendChild(name)

      if (suggestion.name) {
        const email = document.createElement("span")
        email.dataset.part = "mention-autocomplete-email"
        email.textContent = suggestion.email
        item.appendChild(email)
      }

      item.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.selectSuggestion(index)
      })

      this.menu.appendChild(item)
    })
  },

  openMenu() {
    this.ensureMenu()
    this.menu.hidden = false
    this.positionMenu()
    this.el.setAttribute("aria-expanded", "true")
    this.el.setAttribute("aria-activedescendant", `${this.menu.id}-option-${this.activeIndex}`)
  },

  closeMenu() {
    this.menu.hidden = true
    this.el.setAttribute("aria-expanded", "false")
    this.el.removeAttribute("aria-activedescendant")
  },

  positionMenu() {
    if (!this.range || this.menu.hidden) return

    const wrapper = this.el.parentElement
    const wrapperRect = wrapper.getBoundingClientRect()
    const textareaRect = this.el.getBoundingClientRect()
    const coordinates = caretCoordinates(this.el, this.range.end)
    const menuWidth = Math.min(360, wrapper.clientWidth)
    const left = textareaRect.left - wrapperRect.left + coordinates.left
    const top = textareaRect.top - wrapperRect.top + coordinates.top + 4

    this.menu.style.width = `${menuWidth}px`
    this.menu.style.transform = `translate(${Math.round(
      clamp(left, 0, Math.max(0, wrapper.clientWidth - menuWidth))
    )}px, ${Math.round(top)}px)`
  },

  onKeydown(event) {
    if (this.menu.hidden) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.activeIndex = (this.activeIndex + 1) % this.matches.length
      this.renderMenu()
      this.openMenu()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.activeIndex = (this.activeIndex - 1 + this.matches.length) % this.matches.length
      this.renderMenu()
      this.openMenu()
    } else if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault()
      this.selectSuggestion(this.activeIndex)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.closeMenu()
    }
  },

  selectSuggestion(index) {
    const suggestion = this.matches[index]
    if (!suggestion || !this.range) return

    const replacement = `@${suggestion.token} `
    const before = this.el.value.slice(0, this.range.start)
    const after = this.el.value.slice(this.range.end)
    const cursor = before.length + replacement.length

    this.el.value = `${before}${replacement}${after}`
    this.el.setSelectionRange(cursor, cursor)
    this.el.dispatchEvent(new Event("input", { bubbles: true }))
    this.el.focus()
    this.closeMenu()
  },
}

export default MentionAutocomplete
