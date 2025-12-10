# This job is deprecated - scene prompt evolution is now handled in GenerateChatResponseJob.
# Keeping for backward compatibility with queued jobs.
class EvolveScenePromptJob < ApplicationJob
  queue_as :default

  def perform(conversation, assistant_message, previous_prompt)
    Rails.logger.info "EvolveScenePromptJob is deprecated, using ScenePromptService directly"

    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")
    last_user_msg = conversation.messages.where(role: "user").order(:created_at).last

    prompt = ScenePromptService.new(conversation).generate_prompt(
      last_user_msg&.content.to_s,
      assistant_message.content,
      current_time: current_time,
      previous_prompt: previous_prompt
    )

    if prompt.present? && prompt != previous_prompt
      AiPromptGenerationService.new(conversation).store_scene_prompt(prompt, trigger: "evolve")
      GenerateImagesJob.perform_later(conversation, prompt)
    end
  rescue => e
    Rails.logger.error "Failed to evolve scene prompt: #{e.message}"
  end
end