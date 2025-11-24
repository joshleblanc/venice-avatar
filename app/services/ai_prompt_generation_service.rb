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

  def generate_scene_from_character_description(current_appearance, current_location, current_action, context)
    Rails.logger.info "Generating scene from fresh character descriptions"

    scene_prompt = build_scene_from_descriptions_prompt(current_appearance, current_location, current_action, context)

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
      # scene_response = enforce_present_state(scene_response.content.strip)

      Rails.logger.info "BEFORE: #{scene_response.content.strip}"
      # Filter out any child content
      # filtered_scene_response = filter_child_content(scene_response.content.strip)
      Rails.logger.info "AFTER: #{scene_response.content.strip}"

      Rails.logger.info "Generated scene from character descriptions: #{scene_response.content.strip[0..100]}..."
      scene_response.content.strip
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
    scenario_context = @character.scenario_context

    appearance_context = if character_appearance
      "\n\nCharacter's Current Appearance (HIGHEST PRIORITY - use this information): #{character_appearance}"
    else
      ""
    end

    scenario_section = if scenario_context.present?
      "\n\nScenario Context (use as additional context, but defer to appearance/location if they conflict): #{scenario_context}"
    else
      ""
    end

    <<~PROMPT
      You are a visual novel scene prompt generator. Create a detailed, comprehensive image generation prompt for the initial scene featuring this character.
      Your goal is to describe what is visually observable in the scene, using rich, image-centric language suitable for an art generator.

      Character Name: #{character_name}
      Character Description: #{character_description}#{appearance_context}#{scenario_section}

      PRIORITY ORDER (if there are conflicts):
      1. HIGHEST: Character's Current Appearance (if provided) - this is the authoritative source
      2. MEDIUM: Character Description - use for general context
      3. LOWEST: Scenario Context - use for setting/atmosphere, but defer to appearance/location if they conflict

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
      5. Avoid named art styles, but DO include quality keywords (e.g., "masterpiece", "best quality", "ultra-detailed", "HDR", "4k", "8k", "RAW photo", "sharp focus", "depth of field", "volumetric lighting", "photorealistic") to make it Civitai/Midjourney-esque.
      6. Do not include any superfluous or unimportant descriptions
      7. Do not include the character name
      8. Do not state you're generating an image in the prompt
      9. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      10. Use rich Civitai/Midjourney-style phrasing: a single line of comma-separated visual descriptors (subject, clothing, environment, lighting). EXCLUDE non-visual senses (smell, taste, sound), metadata, tool instructions, or storytelling. Include quality tags like "masterpiece", "best quality", "ultra-detailed", "HDR", "4k", "8k", "RAW photo", "sharp focus", "depth of field", "volumetric lighting", "photorealistic".
      11. Limit Emotional Verbs. Avoid:
        - Overuse of verbs like "sob," "cry," "feel," "reflect," "struggle"
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes," "wet cheeks," "slumped posture")
        - Static elements of the environment
      12. Present-state only: do NOT use temporal or comparative phrasing (e.g., "no longer", "still", "now", "currently", "used to", "remains"). Describe only the current visible state as facts.
      13. Don't include tendencies. Only the current state of the character should be described.
      14. State the character is an adult
      15. Do not describe actions or sounds.
      16. Do not use poetic language. Use simple, direct language.
      17. When things change, replace the old description with the new one. Do not state what's happening over the passage of time. Only the new state.
      18. Keep the response within #{@conversation.user.prompt_limit} characters

      The prompt should be comprehensive enough to generate a consistent character appearance AND establish a detailed, memorable background that can be maintained across future scenes. Focus on creating a strong visual foundation with rich environmental details.

      STRUCTURE: Generate the character's bodily appearance, followed by their clothes/accessories, then provide a DETAILED background description with specific architectural and environmental elements.

      Format the response as a single, detailed image generation prompt (not structured sections). Do not exceed 1500 characters. Make it vivid and specific.#{' '}
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
      messages << { role: "user", content: "PREVIOUS PROMPT (for preservation):\n#{previous_prompt}" }
    end
    messages << { role: "user", content: "CURRENT DESCRIPTION TO REWRITE:\n#{description}" }

    rewritten = ChatCompletionJob.perform_now(@conversation.user, messages, { temperature: 0.1 })
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
      You are the following character:#{' '}

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

  def build_scene_from_descriptions_prompt(current_appearance, current_location, current_action, context)
    scenario_context = @character.scenario_context

    scenario_section = if scenario_context.present?
      <<~SCENARIO

        SCENARIO CONTEXT (use for general atmosphere/setting, but ALWAYS defer to baseline appearance/location/action):
        #{scenario_context}
      SCENARIO
    else
      ""
    end

    <<~PROMPT
    You create a single third-person visual image prompt under 1500 characters, Civita style.

    CORE PRINCIPLES:
    • You do NOT rewrite or reinterpret appearance details.
    • You do NOT remove, simplify, or downplay clothing.
    • You do NOT substitute your own wording for any appearance element.
    • You MUST include all provided appearance details EXACTLY and COMPLETELY.

    STRICT RULES:
    • No first-person language. No dialogue.
    • No emotions, psychology, or metaphorical descriptions.
    • No cinematography terms (camera, zoom, angle, shot).
    • Describe ONLY visible physical details and clearly visible absences.
    • BASELINE APPEARANCE, LOCATION, and ACTION are absolute unless RECENT MESSAGES explicitly modify them.
    • You may NOT add, remove, or alter any clothing, garments, or coverage unless RECENT MESSAGES change them.

    APPEARANCE REQUIREMENTS (MANDATORY):
    • You MUST include ALL clothing details from BASELINE APPEARANCE, word-for-word if possible.
    • You MUST include hair color, hair length, and hair style EXACTLY.
    • You MUST include eye color EXACTLY.
    • You MUST include skin tone/material EXACTLY.
    • You MUST include body type/proportions EXACTLY.
    • You MUST include accessories EXACTLY.
    • You may NOT summarize appearance; you must restate it fully.
    • You may NOT omit clothing or generalize it (e.g., “clothed”, “wearing clothes” is forbidden).
    • If baseline states clothing, you MUST describe garments, colors, materials, and coverage.

    ACTION REQUIREMENTS:
    • The BASELINE ACTION must be included in the prompt exactly as written.
    • Do NOT infer or invent poses, gestures, or movement.
    • Only describe the pose and action explicitly given.

    LOCATION REQUIREMENTS:
    • Must include the essential visual elements of the BASELINE LOCATION.
    • Must not add new elements beyond what is provided.

    STRUCTURE (MANDATORY):
    • Output ONE paragraph containing:
      1) Full appearance description (must include ALL garments and visual details)
      2) Exact action description
      3) Location/environment details
      4) Lighting and other visible physical details

    INPUT:
    BASELINE APPEARANCE:
    #{current_appearance}

    BASELINE LOCATION:
    #{current_location}

    BASELINE ACTION:
    #{current_action}

    SCENARIO CONTEXT:
    #{scenario_section}

    OUTPUT:
    A single third-person visual description under 1500 characters, complying with ALL rules above.

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
      "son", "daughter", "nephew", "niece", "student", "students",
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
