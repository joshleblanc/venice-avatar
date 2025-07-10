class AiPromptGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  # Generate initial detailed scene prompt when conversation starts
  def generate_initial_scene_prompt
    Rails.logger.info "Generating initial scene prompt for character: #{@character.name}"

    # First, get character's appearance details
    character_appearance = get_character_appearance_details

    # Then generate the scene prompt using the appearance details
    generate_initial_scene_prompt_with_appearance(character_appearance)
  end

  # Generate initial scene prompt with provided appearance details
  def generate_initial_scene_prompt_with_appearance(character_appearance)
    Rails.logger.info "Generating initial scene prompt with appearance for character: #{@character.name}"

    prompt = build_initial_prompt_generation_request(character_appearance)

    begin
      generated_prompt = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "user",
          content: prompt,
        },
      ], {
        temperature: 0.7,
      })
      Rails.logger.info "Generated initial scene prompt: #{generated_prompt}"

      # Store the prompt in the conversation or character state
      store_scene_prompt(generated_prompt, trigger: "initial")

      generated_prompt
    rescue => e
      Rails.logger.error "Failed to generate initial scene prompt: #{e.message}"
      # Fallback to basic prompt
      fallback_initial_prompt
    end
  end

  # Evolve the scene prompt based on new message content
  def evolve_scene_prompt(previous_prompt, new_message_content, message_timestamp = nil)
    Rails.logger.info "Evolving scene prompt based on new message"

    prompt = build_prompt_evolution_request(previous_prompt, new_message_content, message_timestamp)

    begin
      evolved_prompt = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "user",
          content: prompt,
        },
      ], {
        temperature: 0.3,  # Lower temperature for consistency
      })

      Rails.logger.info "Evolved scene prompt: #{evolved_prompt}"

      # Store the updated prompt
      store_scene_prompt(evolved_prompt, trigger: "evolution")

      evolved_prompt
    rescue => e
      Rails.logger.error "Failed to evolve scene prompt: #{e.message}"
      # Fallback to previous prompt
      previous_prompt
    end
  end

  # Get the current scene prompt for image generation
  def get_current_scene_prompt
    # Try to get from conversation metadata first
    if @conversation.metadata.present? && @conversation.metadata["current_scene_prompt"]
      return @conversation.metadata["current_scene_prompt"]
    end

    # If no prompt exists, generate initial one
    generate_initial_scene_prompt
  end

  private

  def build_initial_prompt_generation_request(character_appearance = nil)
    character_description = @character.description || "A character"
    character_name = @character.name || "Character"

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
      15. Keep the response within #{@conversation.user.prompt_limit} characters

      The prompt should be comprehensive enough to generate a consistent character appearance that can be evolved in future scenes. Focus on establishing a strong visual foundation.

      Generate the character's bodily apperance, followed by their clothes/accessories. Finally the background.

      Format the response as a single, detailed image generation prompt (not structured sections). Do not exceed 1500 characters. Make it vivid and specific. 
    PROMPT
  end

  def build_prompt_evolution_request(previous_prompt, new_message_content, message_timestamp = nil)
    # Calculate time context if timestamp is provided
    time_context = ""
    if message_timestamp
      # Get the last scene prompt update time from conversation metadata
      last_update_time = @conversation.metadata&.dig("scene_prompt_updated_at")
      if last_update_time
        last_time = Time.parse(last_update_time)
        current_time = message_timestamp.is_a?(Time) ? message_timestamp : Time.parse(message_timestamp.to_s)
        time_diff_hours = ((current_time - last_time) / 1.hour).round(1)

        if time_diff_hours >= 1
          time_context = "\n\nTIME CONTEXT: #{time_diff_hours} hours have passed since the last scene update. "
          if time_diff_hours >= 8
            time_context += "This is a significant time gap - the character may have changed clothes, location, or activities."
          elsif time_diff_hours >= 2
            time_context += "Some time has passed - minor changes to appearance or setting may be appropriate."
          end
        end
      end
    end

    <<~PROMPT
      You are a visual novel scene prompt evolution specialist. You need to update an existing scene prompt based on new story content.

      PREVIOUS SCENE PROMPT:
      #{previous_prompt}

      NEW MESSAGE CONTENT:
      #{new_message_content} #{time_context}

      Analyze the new message content and update the scene prompt with MINIMAL changes to reflect ONLY the character's own state and reactions:
      - Character expression or emotion changes (based on their dialogue/reactions)
      - Character clothing or appearance changes (if they mention changing clothes)
      - Character location changes (if they mention moving somewhere)
      - Character pose or activity changes (based on their actions)
      

      DO NOT INCORPORATE:
      - Environmental conditions mentioned by other people (weather, temperature, humidity, etc.)
      - Background elements described by others unless the character explicitly reacts to them
      - Physical effects on the character caused by conditions others mention (sweating, shivering, etc.)

      IMPORTANT RULES:
      1. Keep the character's core appearance consistent (don't change fundamental features)
      2. Only modify elements that represent the CHARACTER'S OWN state, actions, or explicit mentions
      3. Maintain the same art style and quality specifications
      4. If no visual changes to the character are needed, return the previous prompt unchanged
      5. Make changes subtle and natural - avoid dramatic shifts
      6. Changes to the character should replace the previous character description. For example, if the previous prompt says the character is sad, and the new message says she's screaming in rage, the description of her being sad should be replaced. The new emotion should not be appended.
      7. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      8. Limit Verbosity and Emotional Verbs Ask the model to avoid:
        - Overuse of verbs like "sob," "cry," "feel," "reflect," "struggle"
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes", "wet cheeks", "slumped posture")
        - Static elements of the environment
      9. If items are removed, do not mention them in the prompt. For example, if the previous prompt says the character is wearing a hat, and the new message says she's not wearing a hat, the hat should not be present in the prompt at all. (eg. not "the has is discarded on the floor")
      10. Always describe the character's appearance. if they're naked or missing clothing, state that it is missing.
      11. Do not describe actions or sounds.
      12. Do not use poetic language. Use simple, direct language.
      13. Focus only on what the CHARACTER does, says, or explicitly mentions about themselves - ignore environmental descriptions from others.
      14. Keep the response within #{@conversation.user.prompt_limit} characters

      Return the updated prompt as a single, detailed image generation prompt in under 1500 characters.
    PROMPT
  end

  def store_scene_prompt(prompt, trigger: "unknown")
    # Store in conversation metadata for quick access
    metadata = @conversation.metadata || {}
    metadata["current_scene_prompt"] = prompt
    metadata["scene_prompt_updated_at"] = Time.current.iso8601

    @conversation.update!(metadata: metadata)
    
    # Store in scene prompt history table for analysis
    @conversation.scene_prompt_histories.create!(
      prompt: prompt,
      trigger: trigger,
      character_count: prompt.length
    )
  end

  # Get character's appearance details by asking them directly
  def get_character_appearance_details
    Rails.logger.info "Asking character about their appearance for scene generation"

    appearance_prompt = build_character_appearance_prompt

    begin
      options = {
        temperature: 0.3, # Lower temperature for consistency
      }

      if @character.venice_created?
        options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
      end

      appearance_details = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "user",
          content: appearance_prompt,
        },
      ], options)

      Rails.logger.info "Character appearance details: #{appearance_details}"

      # Store the appearance details in conversation metadata for future reference
      store_character_appearance(appearance_details)

      appearance_details
    rescue => e
      Rails.logger.error "Failed to get character appearance details: #{e.message}"
      # Return nil so we fall back to basic description
      nil
    end
  end

  def build_character_appearance_prompt
    <<~PROMPT
      Please describe your current appearance in detail. This will help create an accurate visual representation of you. Include:
      
      - What you're currently wearing (clothing, colors, style)
      - Your hair (color, length, style)
      - Your eye color
      - Any accessories you have on
      - Your current expression or mood
      - Your posture or pose
      
      Be specific and detailed, as this information will be used to generate an image of you. Focus only on your physical appearance that would be visible to someone looking at you right now.
    PROMPT
  end

  def store_character_appearance(appearance_details)
    # Store in conversation metadata alongside scene prompt
    metadata = @conversation.metadata || {}
    metadata["character_appearance_details"] = appearance_details
    metadata["appearance_captured_at"] = Time.current.iso8601

    @conversation.update!(metadata: metadata)
  end

  def fallback_initial_prompt
    character_name = @character.name || "character"
    character_desc = @character.description || "a person"

    "Anime style illustration of #{character_name}, #{character_desc}, standing in a cozy indoor setting, soft lighting, detailed character design, warm atmosphere"
  end
end
