class GenerateChatResponseJob < ApplicationJob
  include CharacterToolCalls

  CHAT_GUIDELINES = ""
  queue_as :default

  def perform(conversation, user_message)
    Rails.logger.info "Generating chat response for conversation #{conversation.id} (reply + scene prompt)"

    conversation.update(generating_reply: true)
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    begin
      reply_service = StructuredTurnService.new(conversation)
      reply_message = reply_service.generate_reply(user_message&.content.to_s, current_time: current_time, opening: false)
      assistant_message = create_message_with_tool_calls(conversation, reply_message)
      reply_text = assistant_message&.content.to_s.strip

      unless reply_message.respond_to?(:tool_calls) && reply_message.tool_calls.present?
        previous_prompt = conversation.metadata&.dig("current_scene_prompt")
        prompt = ScenePromptService.new(conversation).generate_prompt(
          user_message&.content.to_s,
          reply_text,
          current_time: current_time,
          previous_prompt: previous_prompt
        )

        if prompt.present?
          prompt_service = AiPromptGenerationService.new(conversation)
          prompt_service.store_scene_prompt(prompt, trigger: "reply")
          GenerateImagesJob.perform_later(conversation, reply_text, assistant_message&.created_at, prompt)
        end
      end
    rescue => e
      Rails.logger.error "Failed to generate chat response: #{e.message}"
      conversation.messages.create!(
        content: "Error generating chat response: #{e.message}",
        role: "assistant",
        user: conversation.user
      )
    ensure
      conversation.update(generating_reply: false)
    end
  end

  private
end
