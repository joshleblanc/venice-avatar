class GenerateImagesJob < ApplicationJob
  limits_concurrency to: 1, key: ->(conversation, *_args) { ["GenerateImagesJob", conversation.id].join(":") }
  queue_as :default

  def perform(conversation, message_content = nil, message_timestamp = nil, prompt_override = nil)
    # Set generating flag to true (this will touch the conversation and trigger refresh)
    conversation.update!(scene_generating: true)

    prompt_service = AiPromptGenerationService.new(conversation)
    prompt_to_use = prompt_override

    unless prompt_to_use.present?
      # Generate fresh scene prompt based on current character state
      Rails.logger.info "Generating fresh scene prompt based on updated character state"
      prompt_to_use = generate_fresh_scene_prompt(conversation, prompt_service)
      trigger = "tool_call_update"
    else
      Rails.logger.info "Using provided prompt override for image generation"
      trigger = "json_turn"
    end

    if prompt_to_use.present?
      prompt_service.store_scene_prompt(prompt_to_use, trigger: trigger)

      image_service = ImageGenerationService.new(conversation)
      scene_image = if prompt_override.present?
        image_service.generate_scene_image_with_prompt(prompt_to_use, message_timestamp)
      else
        image_service.generate_scene_image(message_content, message_timestamp)
      end

      Rails.logger.info "Generated unified scene image with prompt: #{scene_image ? "success" : "failed"}"
    else
      Rails.logger.warn "Failed to generate scene prompt, skipping image generation"
    end
  rescue => e
    Rails.logger.error "Failed to generate scene image: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  ensure
    conversation.update!(scene_generating: false)
  end

  private

  def generate_fresh_scene_prompt(conversation, prompt_service)
    Rails.logger.info "Generating scene from updated appearance: '#{conversation.appearance}', location: '#{conversation.location}', and action: '#{conversation.action}'"

    # Use the updated appearance, location, and action from the conversation
    current_appearance = conversation.appearance || conversation.character.appearance
    current_location = conversation.location || "A comfortable indoor setting"
    current_action = conversation.action || "Standing comfortably, looking directly at the viewer with a warm, friendly expression"

    # Get the latest message for context
    context = conversation.messages.order(:created_at).last(2)&.map(&:content)

    # Generate scene using the updated character state
    prompt_service.generate_scene_from_character_description(current_appearance, current_location, current_action, context)
  rescue => e
    Rails.logger.error "Failed to generate fresh scene prompt: #{e.message}"
    nil
  end
end
