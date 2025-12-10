# Initialize scene for a conversation.
# If no scene prompt exists, generates one. Otherwise regenerates image from existing prompt.
class InitializeSceneJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    Rails.logger.info "Initializing scene for conversation #{conversation.id}"

    prompt = conversation.metadata&.dig("current_scene_prompt")

    if prompt.blank?
      # No prompt yet - generate initial scene prompt
      metadata = conversation.metadata || {}
      unless metadata["initial_prompt_enqueued"]
        metadata["initial_prompt_enqueued"] = true
        conversation.update!(metadata: metadata)
        GenerateInitialScenePromptJob.perform_now(conversation)
      end
    else
      # Already have a prompt - regenerate image
      GenerateImagesJob.perform_later(conversation, prompt)
    end
  end
end
