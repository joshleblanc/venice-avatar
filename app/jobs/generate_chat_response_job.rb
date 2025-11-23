class GenerateChatResponseJob < ApplicationJob
  CHAT_GUIDELINES = ""
  queue_as :default

  def perform(conversation, user_message)
    Rails.logger.info "Generating chat response for conversation #{conversation.id} (reply + scene prompt)"

    conversation.update(generating_reply: true)
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    begin
      reply_service = StructuredTurnService.new(conversation)
      reply_message = reply_service.generate_reply(user_message&.content.to_s, current_time: current_time, opening: false)
      reply_text = reply_message&.content.to_s.strip

      assistant_message = conversation.messages.create!(
        content: reply_text.presence || "I'm here.",
        role: "assistant",
        user: conversation.user
      )

      prompt = ScenePromptService.new(conversation).generate_prompt(
        user_message&.content.to_s,
        reply_text,
        current_time: current_time
      )

      if prompt.present?
        prompt_service = AiPromptGenerationService.new(conversation)
        prompt_service.store_scene_prompt(prompt, trigger: "reply")
        GenerateImagesJob.perform_later(conversation, reply_text, assistant_message.created_at, prompt)
      end
    rescue => e
      Rails.logger.error "Failed to generate chat response: #{e.message}"
      conversation.messages.create!(
        content: "I'm sorry, I couldn't respond right now. Please try again.",
        role: "assistant",
        user: conversation.user
      )
    ensure
      conversation.update(generating_reply: false)
    end
  end

  private
end
