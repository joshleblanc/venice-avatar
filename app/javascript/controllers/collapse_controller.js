import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="collapse"
export default class extends Controller {
  static targets = ["content", "button"]

  // Toggle the visibility of the collapsible content
  toggle() {
    const isHidden = this.contentTarget.classList.contains('hidden')
    
    if (isHidden) {
      this.contentTarget.classList.remove('hidden')
      if (this.hasButtonTarget) {
        this.buttonTarget.title = 'Hide actions/thoughts'
      }
    } else {
      this.contentTarget.classList.add('hidden')
      if (this.hasButtonTarget) {
        this.buttonTarget.title = 'Show actions/thoughts'
      }
    }
  }

  // Show the content
  show() {
    this.contentTarget.classList.remove('hidden')
    if (this.hasButtonTarget) {
      this.buttonTarget.title = 'Hide actions/thoughts'
    }
  }

  // Hide the content
  hide() {
    this.contentTarget.classList.add('hidden')
    if (this.hasButtonTarget) {
      this.buttonTarget.title = 'Show actions/thoughts'
    }
  }
}
