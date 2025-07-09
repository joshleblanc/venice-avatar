import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["short", "full", "shortButton", "fullButton"]

  toggle() {
    this.shortTarget.classList.toggle("hidden")
    this.fullTarget.classList.toggle("hidden")
    this.shortButtonTarget.classList.toggle("hidden")
    this.fullButtonTarget.classList.toggle("hidden")
  }
}
