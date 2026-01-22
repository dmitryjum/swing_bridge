import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { detailFrame: String }

  connect() {
    this.timeout = null
  }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      const form = this.element
      if (this.detailFrameValue) {
        const hidden = form.querySelector("input[name='detail_frame']")
        if (hidden) hidden.remove()
        const marker = document.createElement("input")
        marker.type = "hidden"
        marker.name = "detail_frame"
        marker.value = this.detailFrameValue
        form.appendChild(marker)
      }
      form.requestSubmit()
    }, 250)
  }
}
