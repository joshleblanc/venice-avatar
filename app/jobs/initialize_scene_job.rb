class InitializeSceneJob < ApplicationJob
  def perform(conversation)
    # Generate character's opening message (async)
    GenerateOpeningMessageJob.perform_later(conversation)

    # Always kick off an immediate image generation.
    # If no prompt exists yet, the image service will use a lightweight fallback prompt
    # and smaller resolution for fast-first render, then upgrade once the real prompt arrives.
    GenerateImagesJob.perform_later(conversation)

    # Ensure initial scene prompt is generated if missing
    if conversation.metadata.blank? || conversation.metadata["current_scene_prompt"].blank?
      GenerateInitialScenePromptJob.perform_later(conversation)
    end
  end
end
