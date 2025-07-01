class GenerateImagesJob < ApplicationJob
  queue_as :default

  def perform(conversation, character_state)
    # Set generating flags to true (this will touch the conversation and trigger refresh)
    # Keep both flags for backward compatibility with frontend
    conversation.update!(
      scene_generating: true,
    )

    image_service = ImageGenerationService.new(conversation)

    # Generate unified scene image
    scene_image = image_service.generate_scene_image(character_state)

    Rails.logger.info "Generated unified scene image: #{scene_image ? "success" : "failed"}"
  rescue => e
    Rails.logger.error "Failed to generate scene image: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  ensure
    conversation.update!(
      scene_generating: false,
    )
  end
end
