class GenerateCharacterAppearanceJob < ApplicationJob
  queue_as :default

  def perform(character, user, force = false)
    # Skip if appearance and location already exists
    return if character.appearance.present? && character.location.present? && !force

    @character = character
    @user = user

    Rails.logger.info "Generating appearance and location for character: #{character.name}"

    begin
      user = character.user

      options = {
        temperature: 0.3
      }

      if @character.venice_created?
        options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
      end

      appearance_description = ChatCompletionJob.perform_now(user, [
        {
          role: "system",
          content: build_appearance_generation_instructions
        },
        {
          role: "user",
          content: <<~PROMPT
            Please describe your current appearance and location in detail. This will help create an accurate visual representation of you. Include:
            
            **Appearance:**
            - What you're currently wearing (clothing, colors, style)
            - Your hair (color, length, style)
            - Your eye color
            - Any accessories you have on
            - Your current expression or mood
            - Your posture or pose
            - Your body (height, bust, weight, etc)

            **Location:**
            - Where are you right now? (e.g., a cozy library, a bustling city street, a futuristic spaceship)
            - What is the lighting like? (e.g., dim, bright, natural, artificial)
            - What objects are around you?
            - What is the overall mood or atmosphere of the location?
            
            Be specific and detailed, as this information will be used to generate an image of you.
          PROMPT
        }
      ], {
        temperature: 0.3
      }).content.strip

      # Update character with generated appearance and location
      # Parse the response to separate appearance and location
      appearance = appearance_description.match(/Appearance:(.*)Location:/m)&.captures&.first&.strip
      location = appearance_description.match(/Location:(.*)/m)&.captures&.first&.strip

      character.update!(appearance: appearance, location: location)
      Rails.logger.info "Successfully generated and stored appearance and location for character: #{character.name}"

      GenerateCharacterAvatarJob.perform_later(character, user)
    rescue => e
      Rails.logger.error "Failed to generate character appearance: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  private

  def build_appearance_generation_instructions
    character_instructions = if @character.user_created?
      @character.character_instructions || "You are #{@character.name}. #{@character.description}"
    else
      "%%CHARACTER_INSTRUCTIONS%%"
    end

    <<~INSTRUCTIONS
      You are the following character: 
      
      <character_instructions>
        #{character_instructions}
      </character_instructions>

      You are describing your appearance and location for an image generation model.
      Please provide a detailed description of your appearance and location.
      
      IMPORTANT: You are an adult character (18+ years old). Only describe adult appearance and adult-appropriate locations. Do not reference children, minors, or child-related content.
      
      The output should be in the following format:
      Appearance: [Your appearance description]
      Location: [Your location description]
    INSTRUCTIONS
  end
end
