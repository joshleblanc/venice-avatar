class AiPromptGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  # Generate initial detailed scene prompt when conversation starts
  def generate_initial_scene_prompt
    Rails.logger.info "Generating initial scene prompt for character: #{@character.name}"

    # First, get character's appearance details from stored appearance
    character_appearance = @character.appearance || get_character_appearance_details

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

    # If no prompt exists, enqueue async initial prompt generation ONCE and return a lightweight fallback
    metadata = @conversation.metadata || {}
    unless metadata["initial_prompt_enqueued"]
      metadata["initial_prompt_enqueued"] = true
      @conversation.update!(metadata: metadata)
      GenerateInitialScenePromptJob.perform_later(@conversation)
    end
    fallback_initial_prompt
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
      You are a visual prompt generator. Output a single compact, comma-separated tag list (Civitai-style). No sentences. No articles. No character names.

      Character Name: #{character_name}
      Character Description: #{character_description}#{appearance_context}

      Rules:
      - Tags only, lowercase, comma-separated
      - No quotes, parentheses, brackets, colons, or periods
      - Start with subject/appearance, then clothing, expression, pose, environment, lighting, quality
      - Always include: adult
      - Avoid inner thoughts, actions, or sounds
      - Do not list artists, model names, or copyrighted styles
      - Keep under #{@conversation.user.prompt_limit} characters

      Return ONLY the tag list, for example:
      1woman, professional woman, auburn hair, wavy hair, green eyes, beauty mark above eyebrow, natural makeup, rosy lips, neutral-toned business suit, crisp blouse, tailored pants, confident posture, standing pose, sunlit office, modern interior, large windows, daylight, soft shadows, focused expression, poised demeanor, adult, clean background, sharp focus
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
      You are updating a compact image-generation prompt expressed as a comma-separated tag list.

      PREVIOUS TAG LIST:
      #{previous_prompt}

      NEW MESSAGE CONTENT:
      #{new_message_content} #{time_context}

      Update the tag list with MINIMAL necessary changes that reflect ONLY the character's own state:
      - Expression changes
      - Clothing/appearance changes explicitly mentioned
      - Location/background changes if the character moves
      - Pose or activity changes

      Do NOT incorporate:
      - Conditions mentioned by others
      - Inner thoughts, actions, or sounds

      Rules:
      - Tags only, lowercase, comma-separated; no quotes or brackets
      - Keep core appearance consistent; replace changed tokens rather than appending duplicates
      - Remove tags that no longer apply; deduplicate
      - Always include: adult
      - Return ONLY the final tag list (no prose)
      - Keep under #{@conversation.user.prompt_limit} characters
    PROMPT
  end

  def store_scene_prompt(prompt, trigger: "unknown")
    # Store in conversation metadata for quick access
    normalized = PromptUtils.normalize_tag_list(prompt, max_len: @conversation.user.prompt_limit, always_include: ["adult"]) 
    metadata = @conversation.metadata || {}
    metadata["current_scene_prompt"] = normalized
    metadata["scene_prompt_updated_at"] = Time.current.iso8601

    @conversation.update!(metadata: metadata)

    # Store in scene prompt history table for analysis
    @conversation.scene_prompt_histories.create!(
      prompt: normalized,
      trigger: trigger,
      character_count: normalized.length,
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
    # Store on character if not already present
    if @character.appearance.blank?
      @character.update!(appearance: appearance_details)
      Rails.logger.info "Stored appearance on character: #{@character.name}"

      # Trigger avatar generation now that we have appearance
      @character.generate_avatar_later if @character.user.present?
    end

    # Also store in conversation metadata for backward compatibility
    metadata = @conversation.metadata || {}
    metadata["character_appearance_details"] = appearance_details
    metadata["appearance_captured_at"] = Time.current.iso8601

    @conversation.update!(metadata: metadata)
  end

  def fallback_initial_prompt
    # Compact tag-style fallback
    PromptUtils.normalize_tag_list(
      "adult, person, cozy indoor setting, warm lighting, soft shadows, standing pose, clean background, sharp focus, high detail",
      max_len: @conversation.user.prompt_limit,
      always_include: ["adult"],
    )
  end
end
