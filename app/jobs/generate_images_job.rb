class GenerateImagesJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    # Set generating flag to true (this will touch the conversation and trigger refresh)
    conversation.update!(scene_generating: true)

    image_service = ImageGenerationService.new(conversation)

    # Generate unified scene image - now stored directly on conversation
    scene_image = image_service.generate_scene_image

    Rails.logger.info "Generated unified scene image: #{scene_image ? "success" : "failed"}"
  rescue => e
    Rails.logger.error "Failed to generate scene image: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  ensure
    conversation.update!(scene_generating: false)
  end
end
