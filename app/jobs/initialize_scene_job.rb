class InitializeSceneJob < ApplicationJob
  def perform(conversation)
    # Generate character's opening message (async)
    #GenerateOpeningMessageJob.perform_later(conversation)

    # Generate initial scene prompt and image (async)
    if conversation.metadata.blank? || conversation.metadata["current_scene_prompt"].blank?
      metadata = conversation.metadata || {}
      unless metadata["initial_prompt_enqueued"]
        metadata["initial_prompt_enqueued"] = true
        conversation.update!(metadata: metadata)
        GenerateInitialScenePromptJob.perform_now(conversation)
      else
        Rails.logger.info "Initial scene prompt already enqueued for conversation #{conversation.id}; skipping"
      end
    else
      # If we already have a scene prompt, generate images directly
      GenerateImagesJob.perform_later(conversation)
    end
  end
end
