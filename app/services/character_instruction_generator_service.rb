class CharacterInstructionGeneratorService
  def initialize(character)
    @character = character
    @venice_client = VeniceClient::ChatApi.new
  end

  def generate_instructions
    Rails.logger.info "Generating character instructions for: #{@character.name}"
    
    prompt = build_instruction_generation_prompt
    
    begin
      response = @venice_client.create_chat_completion({
        body: {
          model: "venice-uncensored",
          messages: [
            {
              role: "user",
              content: prompt,
            },
          ],
          max_completion_tokens: 2000,
          temperature: 0.7,
        },
      })

      instructions = response.choices.first[:message][:content].strip
      @character.update!(character_instructions: instructions)
      
      Rails.logger.info "Generated instructions for character #{@character.name}: #{instructions[0..100]}..."
      instructions
    rescue => e
      Rails.logger.error "Failed to generate character instructions: #{e.message}"
      # Fallback instructions
      fallback_instructions = "You are #{@character.name}. #{@character.description}"
      @character.update!(character_instructions: fallback_instructions)
      fallback_instructions
    end
  end

  private

  def build_instruction_generation_prompt
    <<~PROMPT
      Based on the following character description, create detailed character instructions that define their personality, behavior, speech patterns, and how they should interact in conversations.

      Character Name: #{@character.name}
      Character Description: #{@character.description}

      Generate comprehensive character instructions that include:
      1. Personality traits and characteristics
      2. How they speak and communicate (tone, style, vocabulary)
      3. Their interests, likes, and dislikes
      4. How they behave in conversations
      5. Their background and motivations
      6. Any quirks or unique behaviors
      7. How they should respond to different types of messages
      8. Their emotional tendencies and reactions

      The instructions should be detailed enough to create a consistent, engaging character that feels authentic and true to the provided description. Focus on creating a believable personality that would make for interesting conversations.

      Format the response as clear, actionable instructions for an AI to roleplay as this character. Write in second person (You are..., You should..., etc.).
    PROMPT
  end
end
