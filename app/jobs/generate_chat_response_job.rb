# Simplified chat response job:
# 1. Generate plain text reply
# 2. Evolve scene prompt minimally based on conversation
# 3. Generate image from the evolved prompt
class GenerateChatResponseJob < ApplicationJob
  queue_as :default

  def perform(conversation, user_message)
    Rails.logger.info "Generating chat response for conversation #{conversation.id}"

    conversation.update(generating_reply: true)
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    begin
      # Step 1: Generate plain text reply
      reply_service = StructuredTurnService.new(conversation)
      reply_text = reply_service.generate_reply(
        user_message&.content.to_s,
        current_time: current_time,
        opening: false
      )

      # Step 2: Save the assistant message
      assistant_message = conversation.messages.create!(
        content: reply_text.presence || "...",
        role: "assistant",
        user: conversation.user
      )

      # Step 3: Evolve scene prompt based on conversation
      previous_prompt = conversation.metadata&.dig("current_scene_prompt")
      prompt = ScenePromptService.new(conversation).generate_prompt(
        user_message&.content.to_s,
        reply_text,
        current_time: current_time,
        previous_prompt: previous_prompt
      )

      # Step 4: Store and generate image
      if prompt.present?
        AiPromptGenerationService.new(conversation).store_scene_prompt(prompt, trigger: "reply")
        GenerateImagesJob.perform_later(conversation, prompt)
      end
    rescue => e
      Rails.logger.error "Failed to generate chat response: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      conversation.messages.create!(
        content: "I'm having trouble responding right now.",
        role: "assistant",
        user: conversation.user
      )
    ensure
      conversation.update(generating_reply: false)
    end
  end
end
