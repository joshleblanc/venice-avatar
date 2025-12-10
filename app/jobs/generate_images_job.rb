# Simplified image generation job:
# Takes a prompt and generates an image from it.
class GenerateImagesJob < ApplicationJob
  limits_concurrency to: 1, key: ->(conversation, *_args) { ["GenerateImagesJob", conversation.id].join(":") }
  queue_as :default

  def perform(conversation, prompt)
    return unless prompt.present?

    conversation.update!(scene_generating: true)

    Rails.logger.info "Generating image for conversation #{conversation.id}"
    Rails.logger.debug "Prompt: #{prompt[0..200]}..."

    image_service = ImageGenerationService.new(conversation)
    scene_image = image_service.generate_scene_image_with_prompt(prompt)

    Rails.logger.info "Image generation #{scene_image ? 'succeeded' : 'failed'}"
  rescue => e
    Rails.logger.error "Failed to generate image: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  ensure
    conversation.update!(scene_generating: false)
  end
end
