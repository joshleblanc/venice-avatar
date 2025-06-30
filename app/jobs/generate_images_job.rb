class GenerateImagesJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, character_state_id)
    conversation = Conversation.find(conversation_id)
    character_state = CharacterState.find(character_state_id)
    
    image_service = ImageGenerationService.new(conversation)
    
    # Generate images in parallel if possible
    images = image_service.generate_all_images(character_state)
    
    # Broadcast updates to the conversation view
    if images[:character_image] || images[:background_image]
      broadcast_image_updates(conversation, character_state)
    end
  rescue => e
    Rails.logger.error "Failed to generate images: #{e.message}"
  end

  private

  def broadcast_image_updates(conversation, character_state)
    Turbo::StreamsChannel.broadcast_replace_to(
      "conversation_#{conversation.id}",
      target: "character-display",
      partial: "conversations/character_display",
      locals: { conversation: conversation, current_state: character_state }
    )
  end
end
