class GenerateImagesJob < ApplicationJob
  queue_as :default

  def perform(conversation, character_state)
    # Set generating flags to true (this will touch the conversation and trigger refresh)
    character_state.update!(
      character_image_generating: true,
      background_image_generating: true,
    )

    image_service = ImageGenerationService.new(conversation)

    # Generate images
    images = image_service.generate_all_images(character_state)

    # Clear generating flags (this will touch the conversation and trigger refresh)
    character_state.update!(
      character_image_generating: false,
      background_image_generating: false,
    )
  rescue => e
    Rails.logger.error "Failed to generate images: #{e.message}"
    # Clear generating flags even on error
    character_state.update!(
      character_image_generating: false,
      background_image_generating: false,
    )
  end
end
