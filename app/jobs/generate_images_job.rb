class GenerateImagesJob < ApplicationJob
  limits_concurrency to: 1, key: ->(conversation, *_args) { ["GenerateImagesJob", conversation.id].join(":") }
  queue_as :default

  def perform(conversation, message_content = nil, message_timestamp = nil)
    # Set generating flag to true (this will touch the conversation and trigger refresh)
    conversation.update!(scene_generating: true)

    # Generate fresh scene prompt based on current character state
    Rails.logger.info "Generating fresh scene prompt based on updated character state"
    prompt_service = AiPromptGenerationService.new(conversation)

    # Use the updated appearance and location to generate a new scene
    fresh_scene_prompt = generate_fresh_scene_prompt(conversation, prompt_service)

    if fresh_scene_prompt.present?
      # Store the updated scene prompt
      prompt_service.store_scene_prompt(fresh_scene_prompt, trigger: "tool_call_update")

      # Generate image with the fresh scene prompt
      image_service = ImageGenerationService.new(conversation)
      scene_image = image_service.generate_scene_image(message_content, message_timestamp)

      Rails.logger.info "Generated unified scene image with fresh prompt: #{scene_image ? "success" : "failed"}"
    else
      Rails.logger.warn "Failed to generate fresh scene prompt, skipping image generation"
    end
  rescue => e
    Rails.logger.error "Failed to generate scene image: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  ensure
    conversation.update!(scene_generating: false)
  end

  private

  def generate_fresh_scene_prompt(conversation, prompt_service)
    Rails.logger.info "Generating scene from updated appearance: '#{conversation.appearance}' and location: '#{conversation.location}'"

    # Use the updated appearance and location from the conversation
    current_appearance = conversation.appearance || conversation.character.appearance
    current_location = conversation.location || "A comfortable indoor setting"

    # Get the latest message for context
    context = conversation.messages.order(:created_at).last(2)&.map(&:content)

    # Generate scene using the updated character state
    prompt_service.generate_scene_from_character_description(current_appearance, current_location, context)
  rescue => e
    Rails.logger.error "Failed to generate fresh scene prompt: #{e.message}"
    nil
  end
end
