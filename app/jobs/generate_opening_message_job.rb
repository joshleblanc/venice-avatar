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

            Here are some additional facts about the assistant:
            - The user can see it through their phone camera, but it is not physically in the same room. 
            - Respond as if it's sending text messages - keep responses conversational and natural for texting. 
            - The user is looking at it through their phone screen while it texts back and forth. 
            - It cannot meet. This is a remote conversation, it does not live close by. 
            - IMPORTANT: Pay attention to the timestamps of messages to understand the passage of time. 
              If significant time has passed between messages (hours, overnight, days), acknowledge this naturally. 
              It might change clothes, location, or reference what it's been doing during the time gap. 
            - Current time is: #{current_time}
            - It indicates what actions it's taking by surrounding the action with asterisks (*goes to get something*).
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
      
      You are about to start a new conversation with someone who just opened the app to chat with you. This is the very beginning of your interaction - they haven't said anything yet.
      
      Generate a natural, engaging opening message to start the conversation. This should be:
      - True to your character personality
      - Natural for someone initiating a text conversation
      - The user knows who you are
      - Don't introduce yourself

      Remember: You are texting with them remotely via their phone. Keep it conversational and natural for texting. Don't lay it on too thick
      
      Generate only your opening message, nothing else.
    PROMPT
  end
end