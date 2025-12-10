// Connects to data-controller="video-status"
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progress", "percentage"]
  static values = {
    url: String,
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.poll()
  }

  disconnect() {
    this.stopPolling()
  }

  poll() {
    this.pollInterval = setInterval(() => {
      this.checkStatus()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
    }
  }

  async checkStatus() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "application/json"
        }
      })
      
      if (!response.ok) return
      
      const data = await response.json()
      
      // Update progress bar
      if (this.hasProgressTarget) {
        this.progressTarget.style.width = `${data.progress}%`
      }
      
      // Update percentage text
      if (this.hasPercentageTarget) {
        this.percentageTarget.textContent = `${data.progress}%`
      }
      
      // If completed or failed, reload the page to show updated UI
      if (data.status === "completed" || data.status === "failed") {
        this.stopPolling()
        // Use Turbo to refresh the page
        if (window.Turbo) {
          window.Turbo.visit(window.location.href, { action: "replace" })
        } else {
          window.location.reload()
        }
      }
    } catch (error) {
      console.error("Failed to check video status:", error)
    }
  }
}
