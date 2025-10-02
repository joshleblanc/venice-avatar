import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["descriptionField", "descriptionButton", "scenarioField", "scenarioButton", "nameField"]
  static values = {
    enhanceDescriptionUrl: String,
    enhanceScenarioUrl: String
  }

  async enhanceDescription(event) {
    event.preventDefault()
    
    const textarea = this.descriptionFieldTarget
    const button = this.descriptionButtonTarget
    const prompt = textarea.value.trim()
    
    if (!prompt) {
      alert('Please enter a brief character idea first (e.g., "a witty detective with a dark past")')
      return
    }
    
    // Gather additional context from other fields
    const name = this.hasNameFieldTarget ? this.nameFieldTarget.value.trim() : ''
    const scenario = this.hasScenarioFieldTarget ? this.scenarioFieldTarget.value.trim() : ''
    
    // Disable button and show loading state
    button.disabled = true
    const originalText = button.innerHTML
    button.innerHTML = '⏳ Enhancing...'
    
    try {
      const response = await fetch(this.enhanceDescriptionUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ 
          prompt: prompt,
          name: name,
          scenario: scenario
        })
      })
      
      if (!response.ok) {
        throw new Error('Failed to enhance description')
      }
      
      const data = await response.json()
      
      // Update the description field with the enhanced version
      textarea.value = data.description
      
      // If character name was identified, update the name field if it's empty
      if (data.character_name && this.hasNameFieldTarget) {
        const nameField = this.nameFieldTarget
        if (nameField && !nameField.value.trim()) {
          nameField.value = data.character_name
        }
        
        let info = `AI enhanced your character description${data.character_name ? ' for: ' + data.character_name : ''}`
        this.showNotification(info, 'info')
      }
      
      // Auto-resize textarea if needed
      textarea.style.height = 'auto'
      textarea.style.height = textarea.scrollHeight + 'px'
      
    } catch (error) {
      console.error('Error enhancing description:', error)
      alert('Failed to enhance description. Please try again.')
    } finally {
      // Re-enable button
      button.disabled = false
      button.innerHTML = originalText
    }
  }

  async enhanceScenario(event) {
    event.preventDefault()
    
    const textarea = this.scenarioFieldTarget
    const button = this.scenarioButtonTarget
    const prompt = textarea.value.trim()
    
    if (!prompt) {
      alert('Please enter a brief scenario idea first (e.g., "a spicy rooftop romance")')
      return
    }
    
    // Gather additional context from other fields
    const name = this.hasNameFieldTarget ? this.nameFieldTarget.value.trim() : ''
    const description = this.hasDescriptionFieldTarget ? this.descriptionFieldTarget.value.trim() : ''
    
    // Disable button and show loading state
    button.disabled = true
    const originalText = button.innerHTML
    button.innerHTML = '⏳ Enhancing...'
    
    try {
      const response = await fetch(this.enhanceScenarioUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ 
          prompt: prompt,
          name: name,
          description: description
        })
      })
      
      if (!response.ok) {
        throw new Error('Failed to enhance scenario')
      }
      
      const data = await response.json()
      
      // Update the scenario field with the enhanced version
      textarea.value = data.scenario
      
      // If character name was identified, show a notification
      if (data.character_name) {
        let info = `AI enhanced your scenario for character: ${data.character_name}\n\nThe character generator will use this detailed scenario to create an appropriate character.`
        this.showNotification(info, 'info')
      }
      
      // Auto-resize textarea if needed
      textarea.style.height = 'auto'
      textarea.style.height = textarea.scrollHeight + 'px'
      
    } catch (error) {
      console.error('Error enhancing scenario:', error)
      alert('Failed to enhance scenario. Please try again.')
    } finally {
      // Re-enable button
      button.disabled = false
      button.innerHTML = originalText
    }
  }

  showNotification(message, type = 'info') {
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 max-w-md p-4 rounded-lg shadow-lg z-50 ${
      type === 'info' ? 'bg-blue-50 border border-blue-200 text-blue-800' : 'bg-green-50 border border-green-200 text-green-800'
    }`
    notification.style.whiteSpace = 'pre-line'
    notification.innerHTML = `
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
          </svg>
        </div>
        <div class="ml-3 flex-1">
          <p class="text-sm">${message}</p>
        </div>
        <button onclick="this.parentElement.parentElement.remove()" class="ml-3 flex-shrink-0">
          <span class="text-lg">&times;</span>
        </button>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // Auto-remove after 8 seconds
    setTimeout(() => {
      notification.remove()
    }, 8000)
  }
}
