import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="messages"
export default class extends Controller {
  static targets = ["container", "input", "form"]

  connect() {
    this.scrollToBottom()
    
    // Listen for Turbo events to handle scrolling
    document.addEventListener('turbo:morph', this.handleTurboMorph.bind(this))
    document.addEventListener('turbo:submit-start', this.handleSubmitStart.bind(this))
  }

  disconnect() {
    document.removeEventListener('turbo:morph', this.handleTurboMorph.bind(this))
    document.removeEventListener('turbo:submit-start', this.handleSubmitStart.bind(this))
  }

  // Scroll to bottom of messages container
  scrollToBottom() {
    if (this.hasContainerTarget) {
      this.containerTarget.scrollTop = this.containerTarget.scrollHeight
    }
  }

  // Handle form submission - blank input and scroll
  submitMessage(event) {
    // Let the form submit normally, then blank the input
    setTimeout(() => {
      if (this.hasInputTarget) {
        this.inputTarget.value = ""
      }
      this.scrollToBottom()
    }, 0)
  }

  // Handle Turbo morph events (new messages received)
  handleTurboMorph() {
    console.log("Turbo morph detected - scrolling to bottom")
    this.scrollToBottom()
  }

  // Handle form submission start
  handleSubmitStart() {
    this.scrollToBottom()
  }

  // Action to manually scroll to bottom (for typing indicators, etc.)
  scroll() {
    this.scrollToBottom()
  }
}
