class InitializeSceneJob < ApplicationJob
  def perform(conversation)
    # Initialize scene prompt in conversation metadata if not present
    if conversation.metadata.blank? || conversation.metadata["current_scene_prompt"].blank?
      prompt_service = AiPromptGenerationService.new(conversation)
      prompt_service.get_current_scene_prompt # This will generate initial prompt
    end

    # Generate initial scene image
    GenerateImagesJob.perform_later(conversation)
  end
end
