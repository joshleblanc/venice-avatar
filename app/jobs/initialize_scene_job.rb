class InitializeSceneJob < ApplicationJob
  def perform(conversation)
    # Initialize scene prompt in conversation metadata if not present
    if conversation.metadata.blank? || conversation.metadata["current_scene_prompt"].blank?
      prompt_service = AiPromptGenerationService.new(conversation)
      prompt_service.get_current_scene_prompt # This will generate initial prompt
    end

    # Generate character's opening message to initiate the conversation
    generate_character_opening_message(conversation)

    # Generate initial scene image
    GenerateImagesJob.perform_later(conversation)
  end

  private

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
      )

      Rails.logger.info "Character opening message created: #{opening_message[0..100]}..."
    rescue => e
      Rails.logger.error "Failed to generate character opening message: #{e.message}"
      # Create a fallback opening message
      fallback_message = "Hey there! 😊"
      conversation.messages.create!(
        content: fallback_message,
        role: "assistant",
      )
    end
  end

  def build_opening_message_prompt(conversation)
    character_name = conversation.character.name || "Character"
    character_description = conversation.character.description || "a character"

    <<~PROMPT
      You are #{character_name}. #{character_description}
      
      You are about to start a new conversation with someone who just opened the app to chat with you. This is the very beginning of your interaction - they haven't said anything yet.
      
      Generate a natural, engaging opening message to start the conversation. This should be:
      - Friendly and welcoming
      - True to your character personality
      - Something that invites a response
      - Natural for someone initiating a text conversation
      - you know who the person initiating the conversation is
      
      Remember: You are texting with them remotely via their phone. Keep it conversational and natural for texting.
      
      Generate only your opening message, nothing else.
    PROMPT
  end
end
