class GenerateInitialScenePromptJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation) { ["GenerateInitialScenePromptJob", conversation.id].join(":") }

  def perform(conversation)
    Rails.logger.info "Generating initial scene prompt for conversation #{conversation.id}"
    
    character_appearance = conversation.character.appearance
    if character_appearance.blank?
      Rails.logger.info "Character appearance missing; enqueueing async generation"
      GenerateCharacterAppearanceJob.perform_later(conversation.character, conversation.user)
    end
    
    prompt = build_initial_prompt_generation_request(conversation, character_appearance)

    begin
      generated_prompt = ChatCompletionJob.perform_now(conversation.user, [
        {
          role: "user",
          content: prompt,
        },
      ], {
        temperature: 0.7,
      })
      
      Rails.logger.info "Generated initial scene prompt: #{generated_prompt}"

      # Store the prompt in conversation metadata
      metadata = conversation.metadata || {}
      metadata["current_scene_prompt"] = generated_prompt
      metadata["scene_prompt_updated_at"] = Time.current.iso8601
      conversation.update!(metadata: metadata)

      # Store in scene prompt history table
      conversation.scene_prompt_histories.create!(
        prompt: generated_prompt,
        trigger: "initial",
        character_count: generated_prompt.length,
      )

      # Now that we have the scene prompt, generate the initial scene image
      # Enqueue only once per conversation start
      metadata = conversation.metadata || {}
      if !(metadata["initial_image_enqueued"] || conversation.scene_image.attached? || conversation.scene_generating?)
        metadata["initial_image_enqueued"] = true
        conversation.update!(metadata: metadata)
        GenerateImagesJob.perform_later(conversation)
      else
        Rails.logger.info "Initial scene image already enqueued/present; skipping duplicate enqueue"
      end
    rescue => e
      Rails.logger.error "Failed to generate initial scene prompt: #{e.message}"
      # Do NOT generate an image on fallback. We'll wait until a real prompt is available.
      # Optionally, a retry mechanism could be added here.
    end
  end

  private

  def generate_character_appearance(conversation)
    Rails.logger.info "Generating character appearance for scene prompt"
    
    character_instructions = if conversation.character.user_created?
      conversation.character.character_instructions || "You are #{conversation.character.name}. #{conversation.character.description}"
    else
      "%%CHARACTER_INSTRUCTIONS%%"
    end

    appearance_prompt = <<~PROMPT
      Please describe your current appearance in detail. This will help create an accurate visual representation of you. Include:
      
      - What you're currently wearing (clothing, colors, style)
      - Your hair (color, length, style)
      - Your eye color
      - Any accessories you have on
      - Your current expression or mood
      - Your posture or pose
      
      Be specific and detailed, as this information will be used to generate an image of you. Focus only on your physical appearance that would be visible to someone looking at you right now.
    PROMPT

    options = {
      temperature: 0.3,
    }

    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end

    begin
      appearance_details = ChatCompletionJob.perform_now(conversation.user, [
        {
          role: "system",
          content: <<~PROMPT,
            You are the following character:

            <character_instructions>
                #{character_instructions}
            </character_instructions>

            Please describe your current appearance in detail so an accurate visual representation can be created.
          PROMPT
        },
        {
          role: "user",
          content: appearance_prompt,
        }
      ], options)

      # Store appearance on character for future use
      if conversation.character.appearance.blank?
        conversation.character.update!(appearance: appearance_details)
        conversation.character.generate_avatar_later(conversation.user)
      end

      appearance_details
    rescue => e
      Rails.logger.error "Failed to generate character appearance: #{e.message}"
      nil
    end
  end

  def build_initial_prompt_generation_request(conversation, character_appearance = nil)
    character_description = conversation.character.description || "A character"
    character_name = conversation.character.name || "Character"

    appearance_context = if character_appearance
        "\n\nCharacter's Current Appearance (use this information): #{character_appearance}"
      else
        ""
      end

    <<~PROMPT
      You are a visual novel scene prompt generator. Create a detailed, comprehensive image generation prompt for the initial scene featuring this character:
      You are a visual prompt generator. Your goal is to describe what is visually observable in the scene, using concise, image-centric language suitable for an art generator
      
      Character Name: #{character_name}
      Character Description: #{character_description}#{appearance_context}

      Generate a detailed prompt that includes:
      1. Character appearance (physical features, clothing, expression, pose) - USE THE PROVIDED APPEARANCE DETAILS IF AVAILABLE
      2. Environment/setting (location, background elements, lighting)
      3. Atmosphere and mood
      4. NO Art style specifications
      5. No not include any superfluous, unimportant descriptions.
      6. Do not include the character name
      7. Do not state you're generating an image in the prompt
      8. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      9. Limit Verbosity and Emotional Verbs Ask the model to avoid:
        - Overuse of verbs like "sob," "cry," "feel," "reflect," "struggle"
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes," "wet cheeks," "slumped posture")
        - Static elements of the environment
      10. Don't include tendencies. Only the current state of the character should be described.
      11. State the character is an adult
      12. Do not describe actions or sounds.
      13. Do not use poetic language. Use simple, direct language.
      14. When things change, replace the old description with the new one. Do not state what's happening over the passage of time. Only the new state.
      15. Keep the response within #{conversation.user.prompt_limit} characters

      The prompt should be comprehensive enough to generate a consistent character appearance that can be evolved in future scenes. Focus on establishing a strong visual foundation.

      Generate the character's bodily apperance, followed by their clothes/accessories. Finally the background.

      Format the response as a single, detailed image generation prompt (not structured sections). Do not exceed 1500 characters. Make it vivid and specific. 
    PROMPT
  end

  def build_fallback_prompt(conversation)
    character_name = conversation.character.name || "character"
    character_desc = conversation.character.description || "a person"

    "Anime style illustration of #{character_name}, #{character_desc}, standing in a cozy indoor setting, soft lighting, detailed character design, warm atmosphere"
  end
end
