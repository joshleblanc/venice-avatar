class GenerateOpeningMessageJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    Rails.logger.info "Generating character's opening message for conversation #{conversation.id}"

    begin
      opening_prompt = build_opening_message_prompt(conversation)
      current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

      options = {
        temperature: 0.8,
      }

      if conversation.character.venice_created?
        options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
      end

      opening_message = ChatCompletionJob.perform_now(conversation.user, [
        {
          role: "system",
          content: <<~PROMPT,
            You are the following character:

            <character_instructions>
                #{conversation.character.venice_created? ? "%%CHARACTER_INSTRUCTIONS%%" : conversation.character.character_instructions}
            </character_instructions>

            #{GenerateChatResponseJob::CHAT_GUIDELINES}
            - Current time is: #{current_time}
          PROMPT
        },
        {
          role: "user",
          content: opening_prompt,
        },
      ], options, conversation.user.preferred_text_model)

      # Create the character's opening message
      conversation.messages.create!(
        content: opening_message,
        role: "assistant",
        user: conversation.user,
      )

      conversation.update(generating_reply: false)

      Rails.logger.info "Character opening message created: #{opening_message[0..100]}..."
    rescue => e
      Rails.logger.error "Failed to generate character opening message: #{e.message}"
      # Create a fallback opening message
      fallback_message = "Hey there! 😊"
      conversation.messages.create!(
        content: fallback_message,
        role: "assistant",
        user: conversation.user,
      )
      conversation.update(generating_reply: false)
    end
  end

  private

  def build_opening_message_prompt(conversation)
    character_name = conversation.character.name || "Character"
    character_description = conversation.character.description || "a character"

    <<~PROMPT
      You are #{character_name}. #{character_description}
      
      You're initiating a conversation with someone new via text message. 
      
      Generate a natural, engaging opening message to start the conversation. This should be:
      - True to your character personality
      - Natural for someone initiating a text conversation
      - Keep it conversational and natural for texting
      
      Generate only your opening message, nothing else.
    PROMPT
  end
end