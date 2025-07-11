class EvolveScenePromptJob < ApplicationJob
  queue_as :default

  def perform(conversation, assistant_message, previous_prompt)
    Rails.logger.info "Evolving scene prompt for conversation #{conversation.id}"

    begin
      # Evolve the scene prompt
      prompt_service = AiPromptGenerationService.new(conversation)
      evolved_prompt = prompt_service.evolve_scene_prompt(
        previous_prompt, 
        assistant_message.content, 
        assistant_message.created_at
      )

      # Generate images if the prompt changed
      if evolved_prompt != previous_prompt
        Rails.logger.info "Scene prompt evolved, generating new images"
        GenerateImagesJob.perform_later(conversation, assistant_message.content, assistant_message.created_at)
      else
        Rails.logger.info "Scene prompt unchanged, skipping image generation"
      end
    rescue => e
      Rails.logger.error "Failed to evolve scene prompt: #{e.message}"
      # Generate images with previous prompt as fallback
      GenerateImagesJob.perform_later(conversation, assistant_message.content, assistant_message.created_at)
    end
  end
end