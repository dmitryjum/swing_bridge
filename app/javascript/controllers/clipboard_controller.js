import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }

  copy(event) {
    const text = this.textValue || event.currentTarget.dataset.clipboardTextValue
    if (!text) return
    navigator.clipboard.writeText(text)
  }
}
