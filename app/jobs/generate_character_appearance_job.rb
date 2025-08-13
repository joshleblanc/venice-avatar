class GenerateCharacterAppearanceJob < ApplicationJob
  queue_as :default

  def perform(character)

    # Skip if appearance already exists
    return if character.appearance.present?

    Rails.logger.info "Generating appearance description for character: #{character.name}"

    begin
      appearance_description = ChatCompletionJob.perform_now(character.user, [
        {
          role: "system",
          content: build_appearance_generation_instructions,
        },
        {
          role: "user",
          content: "Character: #{character.name}\n\nDescription: #{character.description}",
        },
      ], {
        temperature: 0.3,
      })

      # Update character with generated appearance
      character.update!(appearance: appearance_description)
      Rails.logger.info "Successfully generated and stored appearance for character: #{character.name}"

      GenerateCharacterAvatarJob.perform_later(character)
    rescue => e
      Rails.logger.error "Failed to generate character appearance: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  private

  def build_appearance_generation_instructions
    <<~INSTRUCTIONS
      You are a character appearance specialist. Extract and generate detailed physical appearance descriptions from character backgrounds.

      Your task:
      1. Analyze the character description for any explicit physical details
      2. Infer appropriate physical characteristics based on background, culture, age, profession
      3. Generate a comprehensive appearance description suitable for image generation and roleplay

      Include these elements:
      - Age and general build
      - Ethnicity/heritage if mentioned or culturally relevant
      - Hair color, length, and style
      - Eye color
      - Facial features and expression tendencies
      - Typical clothing style based on profession/personality
      - Any distinctive features or accessories
      - Overall demeanor and presence

      Guidelines:
      - Be detailed but concise
      - Focus on visual elements
      - Consider cultural context and profession
      - Maintain consistency with the character's background
      - Use clear, descriptive language
      - Avoid personality traits - focus on physical appearance only
      - Detail only a single outfit

      Format as a detailed paragraph describing how this character would physically appear.

      Example output:
      "A 35-year-old Japanese-Argentine woman with shoulder-length wavy black hair often tied back in a practical ponytail. She has warm brown eyes behind stylish reading glasses, with laugh lines that hint at her humor. Her build is slender but confident, often dressed in comfortable yet artistic clothing - flowing cardigans, well-fitted jeans, and comfortable flats. Her hands show the careful precision of her origami work, and she typically wears simple silver jewelry including small origami crane earrings. Her expression is typically warm and approachable, with an intelligent, contemplative gaze."
    INSTRUCTIONS
  end
end
