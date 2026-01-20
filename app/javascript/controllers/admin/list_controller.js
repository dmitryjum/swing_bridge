import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static classes = ["active"]

  select(event) {
    this.itemTargets.forEach(el => el.classList.remove(...this.activeClasses))
    event.currentTarget.classList.add(...this.activeClasses)
  }
}
