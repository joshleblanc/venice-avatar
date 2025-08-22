// Connects to data-controller="autosubmit"
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    const form = this.element.closest("form") || this.element.form
    if (form) {
      if (typeof form.requestSubmit === "function") {
        form.requestSubmit()
      } else {
        form.submit()
      }
    }
  }
}

