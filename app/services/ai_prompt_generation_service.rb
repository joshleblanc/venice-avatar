class AiPromptGenerationService
  class FakeResponse 
    attr_accessor :content 
    def initialize(content)
      @content = content
    end
  end
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

  def store_scene_prompt(prompt, trigger: "unknown")
    Rails.logger.info "Storing scene prompt: #{prompt}"
    prompt = if prompt.respond_to? :content 
               prompt.content.strip 
             else 
               prompt 
             end

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

    # Extract and store background information for consistency
    extract_and_store_background_info(prompt)
  end

  # Generate initial scene prompt with provided appearance details
  def generate_initial_scene_prompt_with_appearance(character_appearance)
    Rails.logger.info "Generating initial scene prompt with appearance for character: #{@character.name}"

    prompt = build_initial_prompt_generation_request(character_appearance)

    begin
      generated_prompt = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "user",
          content: prompt
        }
      ], {
        temperature: 0.7
      })
      # Enforce present-state description (no temporal/negation phrasing)
      # generated_prompt = enforce_present_state(generated_prompt)
      Rails.logger.info "Generated initial scene prompt: #{generated_prompt}"

      # Filter out any child content before storing
      filtered_prompt = filter_child_content(generated_prompt.content.strip)

      # Store the filtered prompt in the conversation or character state
      store_scene_prompt(filtered_prompt, trigger: "initial")

      FakeResponse.new(filtered_prompt)
    rescue => e
      Rails.logger.error "Failed to generate initial scene prompt: #{e.message}, #{e.backtrace}"
      # Fallback to basic prompt
      fallback_initial_prompt
    end
  end

  # Evolve the scene prompt based on new message content
  def evolve_scene_prompt(previous_prompt, new_message_content, message_timestamp = nil)
    Rails.logger.info "Generating fresh scene based on character self-description"

    begin
      # Ask character for their current appearance and location
      current_appearance = get_character_current_appearance
      current_location = get_character_current_location

      # Generate scene based on fresh character descriptions
      scene_prompt = generate_scene_from_character_description(current_appearance, current_location, new_message_content)

      Rails.logger.info "Generated fresh scene prompt: #{scene_prompt}"

      # Filter out any child content before storing
      filtered_scene_prompt = filter_child_content(scene_prompt)

      # Store the filtered prompt
      store_scene_prompt(filtered_scene_prompt, trigger: "character_description")

      filtered_scene_prompt
    rescue => e
      Rails.logger.error "Failed to generate scene from character description: #{e.message}"
      # Fallback to previous prompt or default
      previous_prompt || get_default_scene_prompt
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

  def generate_scene_from_character_description(current_appearance, current_location, context)
    Rails.logger.info "Generating scene from fresh character descriptions"

    scene_prompt = build_scene_from_descriptions_prompt(current_appearance, current_location, context)

    begin
      scene_response = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "user",
          content: scene_prompt
        }
      ], {
        temperature: 0.8  # Higher creativity for rich scene generation
      })

      # Enforce present-state description
      scene_response = enforce_present_state(scene_response.content.strip)

      # Filter out any child content
      filtered_scene_response = filter_child_content(scene_response)

      Rails.logger.info "Generated scene from character descriptions: #{filtered_scene_response[0..100]}..."
      filtered_scene_response
    rescue => e
      Rails.logger.error "Failed to generate scene from descriptions: #{e.message}"
      # Fallback to a basic scene
      "#{@character.name} sits comfortably in a pleasant environment, engaged in conversation."
    end
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
      You are a visual novel scene prompt generator. Create a detailed, comprehensive image generation prompt for the initial scene featuring this character.
      Your goal is to describe what is visually observable in the scene, using concise, image-centric language suitable for an art generator.
      
      Character Name: #{character_name}
      Character Description: #{character_description}#{appearance_context}

      Generate a detailed prompt that includes:
      1. Character appearance (physical features, clothing, expression, pose) - USE THE PROVIDED APPEARANCE DETAILS IF AVAILABLE. If appearance is not provided, infer a coherent appearance consistent with the character description.
      2. DETAILED Environment/setting with specific background elements:
         - Specific location type (indoor/outdoor, room type, landscape, etc.)
         - Architectural details (walls, floors, ceilings, structures)
         - Furniture and objects (tables, chairs, decorations, props)
         - Lighting conditions (natural/artificial, direction, quality, time of day)
         - Atmospheric elements (weather, ambiance, mood lighting)
         - Color palette for the environment
         - Spatial layout and depth elements
      3. Atmosphere and mood that complements the environment
      4. Grounding in the character description: translate relevant elements of the description into visual cues (e.g., clothing style, accessories/props, environment choices). Do not restate the description verbatim; incorporate it visually.
      5. NO Art style specifications
      6. Do not include any superfluous or unimportant descriptions
      7. Do not include the character name
      8. Do not state you're generating an image in the prompt
      9. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      10. Limit Verbosity and Emotional Verbs. Avoid:
        - Overuse of verbs like "sob," "cry," "feel," "reflect," "struggle"
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes," "wet cheeks," "slumped posture")
        - Static elements of the environment
      11. Present-state only: do NOT use temporal or comparative phrasing (e.g., "no longer", "still", "now", "currently", "used to", "remains"). Describe only the current visible state as facts.
      12. Don't include tendencies. Only the current state of the character should be described.
      13. State the character is an adult
      14. Do not describe actions or sounds.
      15. Do not use poetic language. Use simple, direct language.
      16. When things change, replace the old description with the new one. Do not state what's happening over the passage of time. Only the new state.
      17. Keep the response within #{@conversation.user.prompt_limit} characters

      The prompt should be comprehensive enough to generate a consistent character appearance AND establish a detailed, memorable background that can be maintained across future scenes. Focus on creating a strong visual foundation with rich environmental details.

      STRUCTURE: Generate the character's bodily appearance, followed by their clothes/accessories, then provide a DETAILED background description with specific architectural and environmental elements.

      Format the response as a single, detailed image generation prompt (not structured sections). Do not exceed 1500 characters. Make it vivid and specific. 
    PROMPT
  end

  def build_prompt_evolution_request(previous_prompt, new_message_content, message_timestamp = nil, stored_background = nil)
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

    # Add stored background context if available
    background_context = ""
    if stored_background.present?
      background_context = "\n\nSTORED BACKGROUND REFERENCE (use this to maintain consistency):\n#{stored_background}"
    end

    <<~PROMPT
      You are a visual novel scene prompt evolution specialist. You need to update an existing scene prompt based on new story content, changing as little as possible,
      but providing as much detail as possible. 

      PREVIOUS SCENE PROMPT:
      #{previous_prompt}

      NEW MESSAGE CONTENT:
      #{new_message_content} #{time_context}#{background_context}

      Analyze the new message content and update the scene prompt with MINIMAL changes to reflect ONLY the character's own state and reactions:
      - Character expression or emotion changes (based on their dialogue/reactions)
      - Character clothing or appearance changes (if they mention changing clothes)
      - Incorporate the outcome of actions. For example If the character removes their hat, describe their bare head.
      - Character location changes (ONLY if they explicitly mention moving to a new place)
      - CRITICAL: Preserve the ENTIRE environment/background from the previous prompt VERBATIM unless the character clearly changes location. This includes:
        * All architectural details (walls, floors, ceilings, structures)
        * All furniture and objects (tables, chairs, decorations, props)
        * All lighting conditions and atmospheric elements
        * All color descriptions for the environment
        * All spatial layout and depth elements
        If there is no explicit location change, copy the background description word-for-word from the previous prompt.
      - Character pose or activity changes (based on their actions)
      

      DO NOT INCORPORATE:
      - Environmental conditions mentioned by other people (weather, temperature, humidity, etc.)
      - Background elements described by others unless the character explicitly reacts to them
      - Physical effects on the character caused by conditions others mention (sweating, shivering, etc.)
      - Any changes to lighting, furniture, or environmental details unless the character explicitly mentions them

      IMPORTANT RULES:
      1. Keep the character's core appearance consistent (don't change fundamental features)
      2. Only modify elements that represent the CHARACTER'S OWN state, actions, or explicit mentions
      3. Maintain the same art style and quality specifications
      4. If no visual changes to the character are needed, return the previous prompt unchanged
      5. Make changes subtle and natural - avoid dramatic shifts
      5a. VERBATIM PRESERVATION: Copy unchanged parts of the PREVIOUS SCENE PROMPT exactly as written. Do NOT paraphrase unchanged elements.
      5b. Elements that MUST remain verbatim unless explicitly contradicted by the new message: 
         - Numbers (ages, measurements like 5'2")
         - Colors (for character, clothing, and environment)
         - Proper nouns/place names (e.g., El Dorado)
         - Clothing items and accessories with their colors
         - Face/body descriptors (e.g., "heart-shaped face", "full pink lips", "thick thighs")
         - BACKGROUND DESCRIPTORS: All environmental elements including:
           * Room types and architectural features (e.g., "marble columns", "vaulted ceiling", "hardwood floors")
           * Furniture and objects (e.g., "mahogany desk", "crystal chandelier", "Persian rug")
           * Lighting descriptions (e.g., "warm golden light", "soft morning sunlight", "flickering candlelight")
           * Atmospheric elements (e.g., "misty air", "gentle breeze", "cozy atmosphere")
           * Spatial descriptions (e.g., "spacious room", "narrow hallway", "corner by the window")
      6. Changes to the character should replace the previous character description. For example, if the previous prompt says the character is sad, and the new message says she's screaming in rage, the description of her being sad should be replaced. The new emotion should not be appended.
      7. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      8. Limit Verbosity and Emotional Verbs Ask the model to avoid:
        - Overuse of verbs like "sob," "cry," "feel," "reflect," "struggle"
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes", "wet cheeks", "slumped posture")
        - Static elements of the environment
      9. If items are removed, do not mention them in the prompt. For example, if the previous prompt says the character is wearing a hat, and the new message says she's not wearing a hat, the hat should not be present in the prompt at all. (eg. not "the has is discarded on the floor"). Do NOT remove the environment/background unless the character explicitly changes location.
      10. PRESENT-STATE ONLY: Never write about changes over time. Do not use temporal or comparative phrasing such as "no longer", "still", "now", "currently", "used to", "remains", "continues". Instead, state the resulting current state directly. Examples: "cheeks are no longer flushed" → "cheeks have a normal color"; "no longer wearing a jacket" → omit the jacket and describe the current outfit.
      11. Always describe the character's appearance. if they're naked or missing clothing, state that it is missing.
      12. Do not describe actions or sounds.
      13. Do not use poetic language. Use simple, direct language.
      14. Focus only on what the CHARACTER does, says, or explicitly mentions about themselves - ignore environmental descriptions from others. Keep the background from the previous prompt if unchanged.
      15. BACKGROUND CONSISTENCY: If stored background reference is provided, ensure the final prompt maintains those exact environmental details unless the character explicitly changes location. The background should remain visually consistent across scenes.
      16. Keep the response within #{@conversation.user.prompt_limit} characters

      Return the updated prompt as a single, detailed image generation prompt in under 1500 characters. Ensure background elements remain consistent and detailed.
    PROMPT
  end

  # Ensure the final prompt expresses only present visual state (no temporal/negation phrasing)
  def enforce_present_state(description, previous_prompt = nil)
    messages = [
      {
        role: "system",
        content: <<~SYS
          Rewrite the user's scene description to express ONLY the present visual state.
          - Remove temporal/comparative phrasing (e.g., "no longer", "still", "now", "currently", "used to", "remains", "continues").
          - Do not describe changes; only the resulting state should be described.
          - If something is absent, either omit it or describe what is visible instead.
          - Preserve the meaning faithfully. Do not add new details.
          - If a PREVIOUS PROMPT is provided, preserve unchanged descriptors verbatim from it: numbers, measurements (e.g., 5'2"), colors, proper nouns/place names (e.g., El Dorado), clothing items/accessories, body/face descriptors (e.g., "heart-shaped face", "full pink lips", "thick thighs"), and ALL background/environmental elements (furniture, lighting, architectural details, atmospheric elements).
          - Maintain detailed background consistency - environmental descriptions should remain rich and specific.
          - Return just the rewritten description, under 1500 characters.
        SYS
      }
    ]
    if previous_prompt.present?
      messages << {role: "user", content: "PREVIOUS PROMPT (for preservation):\n#{previous_prompt}"}
    end
    messages << {role: "user", content: "CURRENT DESCRIPTION TO REWRITE:\n#{description}"}

    rewritten = ChatCompletionJob.perform_now(@conversation.user, messages, {temperature: 0.1})
    rewritten.content.strip
  rescue => e
    Rails.logger.error "Failed to enforce present-state rewrite: #{e.message}"
    description
  end

  # Get character's appearance details by asking them directly
  def get_character_appearance_details
    Rails.logger.info "Asking character about their appearance for scene generation"

    appearance_prompt = build_character_appearance_prompt

    begin
      options = {
        temperature: 0.3 # Lower temperature for consistency
      }

      if @character.venice_created?
        options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
      end

      appearance_details = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "user",
          content: appearance_prompt
        }
      ], options)

      Rails.logger.info "Character appearance details: #{appearance_details}"

      # Store the appearance details in conversation metadata for future reference
      store_character_appearance(appearance_details.content.strip)

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
      @character.generate_avatar_later(@conversation.user)
    end

    # Also store in conversation metadata for backward compatibility
    metadata = @conversation.metadata || {}
    metadata["character_appearance_details"] = appearance_details
    metadata["appearance_captured_at"] = Time.current.iso8601

    @conversation.update!(metadata: metadata)
  end

  def get_character_current_appearance
    Rails.logger.info "Asking character for their current appearance with conversation context"

    begin
      options = {
        temperature: 0.7  # Allow some creativity in self-description
      }

      if @character.venice_created?
        options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
      end

      # Build conversation messages with appearance request
      messages = build_conversation_messages_for_description("appearance")

      appearance_response = ChatCompletionJob.perform_now(@conversation.user, messages, options)

      Rails.logger.info "Character provided appearance description: #{appearance_response[0..100]}..."
      appearance_response.content.strip
    rescue => e
      Rails.logger.error "Failed to get character appearance: #{e.message}"
      # Fallback to stored character appearance
      @character.appearance || "A person sitting comfortably"
    end
  end

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
    INSTRUCTIONS
  end

  def build_current_appearance_prompt
    <<~PROMPT
      Please describe your current appearance in detail. This will help create an accurate visual representation of you. Include:
      
      - What you're currently wearing (clothing, colors, style)
      - Your hair (color, length, style)
      - Your eye color
      - Any accessories you have on
      - Your current expression or mood
      - Your posture or pose
      - Your body (height, bust, weight, etc)
      
      Be specific and detailed, as this information will be used to generate an image of you. Focus only on your physical appearance that would be visible to someone looking at you right now.
    PROMPT
  end

  def get_character_current_location
    Rails.logger.info "Asking character for their current location and background with conversation context"

    begin
      options = {
        temperature: 0.7  # Allow some creativity in location description
      }

      if @character.venice_created?
        options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
      end

      # Build conversation messages with location request
      messages = build_conversation_messages_for_description("location")

      location_response = ChatCompletionJob.perform_now(@conversation.user, messages, options)

      Rails.logger.info "Character provided location description: #{location_response[0..100]}..."
      location_response.content.strip
    rescue => e
      Rails.logger.error "Failed to get character location: #{e.message}"
      # Fallback to a generic location
      "A comfortable indoor setting with warm lighting"
    end
  end

  def build_current_location_prompt
    <<~PROMPT
      Please describe your current location and surroundings in detail for a visual scene. Include:

      - Where you are right now (room, building, outdoor location, etc.)
      - The type of space and its purpose
      - Furniture and objects around you
      - Lighting conditions (natural light, lamps, mood lighting, etc.)
      - Colors, textures, and materials in the environment
      - Atmospheric details (sounds, smells, temperature, mood)
      - Any distinctive features or decorative elements
      - The overall ambiance and feeling of the space

      Be specific and detailed, as this will be used to create an accurate visual representation of your current environment. Describe the setting as it appears right now during our conversation.

      Focus on the visual elements that would be seen in a scene showing you in this location.

      IMPORTANT: Only describe adult characters and settings. Do not include any references to children, minors, or child-related content in your description.
    PROMPT
  end

  def build_scene_from_descriptions_prompt(current_appearance, current_location, context)
    <<~PROMPT
      You will receive an appearance description and a location description, as well as the last 2 messages description the scene. Generate cohesive image prompt optimized for AI image generators (e.g., MidJourney, DALL-E). Prioritize vivid sensory details, logical spatial integration, and avoid redundancy. Output ONLY the final prompt with no explanations:
      If the context requires additional subjects, invest a generic standin.
      Appearance: #{current_appearance}
      Location: #{current_location}
      Message: #{context.first}
      Reply: #{context.second}      
    PROMPT
  end

  def build_conversation_messages_for_description(description_type)
    messages = []

    # Add system message for the character
    messages << {
      role: "system",
      content: build_description_system_prompt(description_type)
    }

    # Add all conversation messages for context
    @conversation.messages.order(:created_at).each do |message|
      messages << {
        role: message.role,
        content: message.content
      }
    end

    # Add the description request as the final user message
    messages << {
      role: "user",
      content: build_description_request_prompt(description_type)
    }

    messages
  end

  def build_description_system_prompt(description_type)
    case description_type
    when "appearance"
      <<~SYSTEM
        Please describe your current appearance in detail. This will help create an accurate visual representation of you. Include:
        
        - What you're currently wearing (clothing, colors, style)
        - Your hair (color, length, style)
        - Your eye color
        - Any accessories you have on
        - Your current expression or mood
        - Your posture or pose
        - Your body (height, bust, weight, etc)
        
        Be specific and detailed, as this information will be used to generate an image of you. Focus only on your physical appearance that would be visible to someone looking at you right now.
      SYSTEM
    when "location"
      <<~SYSTEM
        You are #{@character.name}. Based on the conversation context, describe your current location and surroundings in detail.
        Consider where you are, what the environment looks like, the lighting, furniture, atmosphere, and any changes that might have occurred during the conversation.
        Be specific and detailed about the setting, ambiance, and environmental elements.
      SYSTEM
    end
  end

  def build_description_request_prompt(description_type)
    case description_type
    when "appearance"
      build_current_appearance_prompt
    when "location"
      build_current_location_prompt
    end
  end

  def get_default_scene_prompt
    prompt = "#{@character.name} sits comfortably in a pleasant, well-lit environment, engaged in friendly conversation with a warm, welcoming expression."
    filter_child_content(prompt)
  end

  def extract_and_store_background_info(prompt)
    # Extract background/environment information from the prompt for future consistency

    extraction_prompt = <<~EXTRACT
      Extract ONLY the background/environment description from this scene prompt. 
      Include all details about:
      - Location and setting
      - Architectural elements
      - Furniture and objects
      - Lighting conditions
      - Atmospheric elements
      - Colors and materials of the environment
      
      Do not include character descriptions. Return only the environmental details as a concise description.
      
      Scene prompt: #{prompt}
    EXTRACT

    background_info = ChatCompletionJob.perform_now(@conversation.user, [
      {
        role: "user",
        content: extraction_prompt
      }
    ], {
      temperature: 0.1  # Very low temperature for consistency
    })

    # Store the extracted background info in conversation metadata
    metadata = @conversation.metadata || {}
    metadata["extracted_background_info"] = background_info.content.strip
    metadata["background_extracted_at"] = Time.current.iso8601

    @conversation.update!(metadata: metadata)

    Rails.logger.info "Extracted background info: #{background_info}"
  rescue => e
    Rails.logger.error "Failed to extract background info: #{e.message}"
  end

  def get_stored_background_info
    # Retrieve previously stored background information
    @conversation.metadata&.dig("extracted_background_info")
  end

  def fallback_initial_prompt
    character_name = @character.name || "character"
    character_desc = @character.description || "a person"

    prompt = "Anime style illustration of #{character_name}, #{character_desc}, standing in a cozy indoor setting with warm wooden furniture, soft ambient lighting from table lamps, cream-colored walls with framed artwork, hardwood floors with a comfortable area rug, detailed character design, warm atmosphere"

    filter_child_content(prompt)
  end

  # Content filtering to ensure no child references in prompts
  #
  # @param [String] content The content to filter
  # @return [String] The filtered content
  def filter_child_content(content)
    return content if content.blank?

    # List of child-related terms to filter out
    child_terms = [
      "child", "children", "kid", "kids", "baby", "babies", "toddler", "toddlers",
      "infant", "infants", "minor", "minors", "boy", "boys", "girl", "girls",
      "son", "daughter", "nephew", "niece", "student", "students", "pupil", "pupils",
      "schoolchild", "schoolchildren", "youngster", "youngsters", "youth", "youths",
      "juvenile", "juveniles", "adolescent", "adolescents", "teen", "teens",
      "teenager", "teenagers", "preteen", "preteens", "tween", "tweens"
    ]

    filtered_content = content.dup

    # Remove sentences containing child-related terms
    sentences = filtered_content.split(/[.!?]+/)
    filtered_sentences = sentences.reject do |sentence|
      child_terms.any? { |term| sentence.downcase.include?(term.downcase) }
    end

    # If all sentences were filtered out, return a safe default
    if filtered_sentences.empty?
      return "An adult character in a comfortable indoor setting with warm lighting."
    end

    filtered_sentences.join(". ").strip + "."
  end
end
