import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="messages"
export default class extends Controller {
  static targets = ["container", "submit", "input", "form"]

  connect() {

    const observer = new MutationObserver(() => { this.scrollToBottom() });

    observer.observe(this.containerTarget, { childList: true });
    this.scrollToBottom();
  }

  // Scroll to bottom of messages container
  scrollToBottom() {
    if (this.hasContainerTarget) {
      this.containerTarget.scrollTop = this.containerTarget.scrollHeight
    }
  }

  submitForm(event) {
    this.submitTarget.click();
    event.preventDefault();
  }

  // Handle form submission - blank input and scroll
  submitMessage(event) {
    // Let the form submit normally, then blank the input
    setTimeout(() => {
      if (this.hasInputTarget) {
        this.inputTarget.value = ""
      }
      // this.scrollToBottom()
    }, 0)
  }
}
