class InitializeSceneJob < ApplicationJob
  def perform(conversation)
    # Generate character's opening message (async)
    GenerateOpeningMessageJob.perform_later(conversation)

    # Generate initial scene prompt and image (async)
    if conversation.metadata.blank? || conversation.metadata["current_scene_prompt"].blank?
      GenerateInitialScenePromptJob.perform_later(conversation)
    else
      # If we already have a scene prompt, generate images directly
      GenerateImagesJob.perform_later(conversation)
    end
  end
end
