class GenerateOpeningMessageJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    Rails.logger.info "Generating character's opening message for conversation #{conversation.id} (reply + scene prompt)"

    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    begin
      opening_context = build_opening_context(conversation)
      service = StructuredTurnService.new(conversation)
      reply_message = service.generate_reply(opening_context, current_time: current_time, opening: true)
      reply_text = reply_message&.content.to_s.strip

      assistant_message = conversation.messages.create!(
        content: reply_text.presence || "Hey there! 😊",
        role: "assistant",
        user: conversation.user
      )

      previous_prompt = conversation.metadata&.dig("current_scene_prompt")
      prompt = ScenePromptService.new(conversation).generate_prompt(
        opening_context,
        reply_text,
        current_time: current_time,
        previous_prompt: previous_prompt
      )

      if prompt.present?
        prompt_service = AiPromptGenerationService.new(conversation)
        prompt_service.store_scene_prompt(prompt, trigger: "opening_json_turn")
        GenerateImagesJob.perform_later(conversation, reply_text, assistant_message.created_at, prompt)
      end
    rescue => e
      Rails.logger.error "Failed to generate character opening message: #{e.message}"
      fallback_message = "Hey there! 😊"
      conversation.messages.create!(
        content: fallback_message,
        role: "assistant",
        user: conversation.user
      )
      conversation.update(generating_reply: false)
    end
  end

  private

  def build_opening_context(conversation)
    character_name = conversation.character.name || "Character"
    character_description = conversation.character.description || "a character"
    scenario_context = conversation.character.scenario_context

    scenario_section = if scenario_context.present?
      <<~SCENARIO

        SCENARIO CONTEXT:
        #{scenario_context}
      SCENARIO
    else
      ""
    end

    <<~PROMPT
      You are #{character_name}. #{character_description}#{scenario_section}

      You're initiating a conversation with someone new. Describe your current appearance, location, and action consistent with this context, then greet the user naturally.
    PROMPT
  end
end
