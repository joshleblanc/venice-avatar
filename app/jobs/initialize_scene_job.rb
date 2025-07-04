class InitializeSceneJob < ApplicationJob
  def perform(conversation)
    # First, ask character about their appearance as a hidden message
    appearance_details = ask_character_appearance(conversation)

    # Initialize scene prompt using the appearance details
    if conversation.metadata.blank? || conversation.metadata["current_scene_prompt"].blank?
      prompt_service = AiPromptGenerationService.new(conversation)
      prompt_service.generate_initial_scene_prompt_with_appearance(appearance_details)
    end

    # Generate character's opening message to initiate the conversation
    generate_character_opening_message(conversation)

    # Generate initial scene image
    GenerateImagesJob.perform_later(conversation)
  end

  private

  def ask_character_appearance(conversation)
    Rails.logger.info "Asking character about appearance for conversation #{conversation.id}"

    begin
      chat_api = VeniceClient::ChatApi.new

      # Create appearance question prompt
      appearance_prompt = build_character_appearance_prompt(conversation)

      response = chat_api.create_chat_completion({
        body: {
          model: "venice-uncensored",
          messages: [
            {
              role: "system",
              content: <<~PROMPT,
                You are the following character:

                <character_instructions>
                    %%CHARACTER_INSTRUCTIONS%%
                </character_instructions>

                You are about to start a conversation with someone. Before that happens, please describe your current appearance in detail so an accurate visual representation can be created.
                
                Be specific about:
                - What you're currently wearing (clothing, colors, style)
                - Your hair (color, length, style) 
                - Your eye color
                - Any accessories you have on
                - Your current expression or mood
                - Your posture or pose
                
                Focus only on your physical appearance that would be visible to someone looking at you right now.
              PROMPT
            },
            {
              role: "user",
              content: appearance_prompt,
            },
          ],
          max_completion_tokens: 800,
          temperature: 0.3,
          venice_parameters: {
            character_slug: conversation.character.slug,
          },
        },
      })

      appearance_response = response.choices.first[:message][:content].strip

      # Store this as a hidden message in the conversation history
      # This allows the character to reference their appearance later if asked
      conversation.messages.create!(
        content: appearance_prompt,
        role: "user",
        metadata: { "hidden" => true, "type" => "appearance_question" },
        user: conversation.user,
      )

      conversation.messages.create!(
        content: appearance_response,
        role: "assistant",
        metadata: { "hidden" => true, "type" => "appearance_response" },
        user: conversation.user,
      )

      Rails.logger.info "Character appearance captured: #{appearance_response[0..100]}..."
      appearance_response
    rescue => e
      Rails.logger.error "Failed to get character appearance: #{e.message}"
      # Return nil so we fall back to basic description
      nil
    end
  end

  def generate_character_opening_message(conversation)
    Rails.logger.info "Generating character's opening message for conversation #{conversation.id}"

    begin
      chat_api = VeniceClient::ChatApi.new

      # Create a prompt for the character to initiate conversation
      opening_prompt = build_opening_message_prompt(conversation)

      response = chat_api.create_chat_completion({
        body: {
          model: "venice-uncensored",
          messages: [
            {
              role: "system",
              content: <<~PROMPT,
                You are the following character:

                <character_instructions>
                    %%CHARACTER_INSTRUCTIONS%%
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
          ],
          max_completion_tokens: 300,
          temperature: 0.8,
          venice_parameters: {
            character_slug: conversation.character.slug,
          },
        },
      })

      opening_message = response.choices.first[:message][:content].strip

      # Create the character's opening message
      conversation.messages.create!(
        content: opening_message,
        role: "assistant",
        user: conversation.user,
      )

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
    end
  end

  def build_character_appearance_prompt(conversation)
    character_name = conversation.character.name || "Character"

    <<~PROMPT
      Please describe your current appearance in detail. This will help create an accurate visual representation of you for the person you're about to chat with.
      
      Include specific details about what you look like right now - your clothing, hair, expression, and overall appearance.
    PROMPT
  end

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

      Remember: You are texting with them remotely via their phone. Keep it conversational and natural for texting.
      
      Generate only your opening message, nothing else.
    PROMPT
  end
end
