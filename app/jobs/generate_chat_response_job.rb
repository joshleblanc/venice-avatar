class GenerateChatResponseJob < ApplicationJob
  queue_as :default

  def perform(conversation, user_message)
    Rails.logger.info "Generating chat response for conversation #{conversation.id}"

    begin
      # Get the current scene prompt before generating response
      prompt_service = AiPromptGenerationService.new(conversation)
      current_prompt = prompt_service.get_current_scene_prompt

      # Generate the chat response
      chat_response = send_to_venice_chat(conversation, user_message.content)

      # Save assistant response
      assistant_msg = conversation.messages.create!(
        content: chat_response, 
        role: "assistant", 
        user: conversation.user
      )
      conversation.update(generating_reply: false)

      Rails.logger.info "Chat response generated: #{chat_response[0..100]}..."

      # Evolve scene prompt and generate images if needed
      EvolveScenePromptJob.perform_later(conversation, assistant_msg, current_prompt)

      # Check if character wants to step away
      followup_detector = FollowupIntentDetectorService.new(conversation)
      followup_intent = followup_detector.detect_character_followup_intent(chat_response)

      if followup_intent[:has_intent] && followup_intent[:duration].to_i > 0
        assistant_msg.update!(
          metadata: { auto_generated: true, reason: followup_intent[:reason] },
        )
        conversation.update!(character_away: true)
        Rails.logger.info "Character stepping away for conversation #{conversation.id}: #{followup_intent[:reason]}"

        CharacterReturnJob.set(wait: followup_intent[:duration].to_i.seconds).perform_later(conversation)
      end
    rescue => e
      Rails.logger.error "Failed to generate chat response: #{e.message}"
      
      conversation.messages.create!(
        content: "I'm sorry, I couldn't respond right now. Please try again.",
        role: "assistant",
        user: conversation.user,
      )
      conversation.update(generating_reply: false)
    end
  end

  private

  def send_to_venice_chat(conversation, message)
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    character_instructions = if conversation.character.user_created?
        conversation.character.character_instructions || "You are #{conversation.character.name}. #{conversation.character.description}"
      else
        "%%CHARACTER_INSTRUCTIONS%%"
      end

    system_message = {
      role: "system",
      content: <<~PROMPT,
        The current time is: #{current_time}

        The assistant is the following character:

        <character_instructions>
            #{character_instructions}
        </character_instructions>

        Your appearance at the beginning of the conversation is: #{conversation.character.appearance}

        Context and Guidelines:
        - This is a text conversation through a phone app - you can see the user through their camera, but you're not physically together
        - You cannot meet in person as this is a remote connection
        - Be aware of time gaps between messages - if hours or days have passed, naturally acknowledge what you've been up to
        - When you do something, you can mention it casually (*grabs a coffee* or *stretches*) - keep it natural, not theatrical
        - Text like a real person would - conversational, authentic, sometimes imperfect
        - You can ask questions when it feels natural to the conversation
        - Don't include timestamps in your messages
      PROMPT
    }

    # Build conversation history
    messages = conversation.messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content,
      }
    end

    options = {}
    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end

    ChatCompletionJob.perform_now(conversation.user, [system_message] + messages, options, conversation.user.preferred_text_model) || "I'm sorry, I couldn't respond right now."
  end
end