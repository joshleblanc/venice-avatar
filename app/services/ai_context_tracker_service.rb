class AiContextTrackerService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @venice_client = VeniceClient::ChatApi.new
  end

  def analyze_message_context(message_content, role)
    # Get current character state for context
    current_state = @conversation.current_character_state

    # Build comprehensive context for AI analysis
    analysis_prompt = build_context_analysis_prompt(message_content, role, current_state)

    # Get AI analysis of the context
    ai_response = request_context_analysis(analysis_prompt)

    # Log the AI response for debugging
    Rails.logger.info "AI Analysis Response: #{ai_response}"

    # Parse AI response into structured data
    context_changes = parse_ai_response(ai_response)

    # Create new character state if significant changes detected
    new_state = create_character_state_if_needed(context_changes, message_content, role, ai_response)

    # Return both the character state and the context analysis
    {
      character_state: new_state,
      context_analysis: context_changes
    }
  end

  private

  def build_context_analysis_prompt(message_content, role, current_state)
    character_info = build_character_context(current_state)

    prompt = <<~PROMPT
      You are an expert at analyzing character interactions in visual novels. Analyze the following message and provide COMPLETE character state information to ensure visual consistency.

      CHARACTER CONTEXT:
      #{character_info}

      MESSAGE TO ANALYZE:
      Role: #{role}
      Content: "#{message_content}"

      CRITICAL REQUIREMENTS:
      You MUST provide complete information for ALL categories below. Never leave fields empty or null.
      If information isn't explicitly mentioned in the message, use the current character context or make reasonable assumptions based on the character's established traits.
      This ensures visual consistency across all generated images.

      CHANGE DETECTION:
      For each category, include a "changed" field (true/false) indicating whether that aspect has changed from the previous state.
      - Set "changed": true ONLY if the message explicitly mentions or implies a change to that category
      - Set "changed": false if the category should remain the same as the previous state
      - Always provide complete details regardless of whether changed is true or false

      ANALYSIS INSTRUCTIONS:
      Provide COMPLETE details for each category with change detection:

      1. PHYSICAL_FEATURES: Always specify age appearance, height, and build
      2. HAIR_DETAILS: Always specify length, color, and current style
      3. EYE_DETAILS: Always specify color and any distinctive features
      4. BODY_DETAILS: Always specify body type and skin tone
      5. DISTINCTIVE_FEATURES: List any scars, tattoos, or unique features
      6. CURRENT_EXPRESSION: Current emotional expression with intensity
      7. CLOTHING: Complete current outfit description
      8. POSE_ACTIVITY: Current pose, activity, and body language
      9. LOCATION_ENVIRONMENT: Complete environment description
      10. INJURIES: Any current injuries or temporary marks
      11. FOLLOW_UP_INTENT: Whether character will send follow-up message

      RESPONSE FORMAT (JSON):
      {
        "physical_features": {
          "changed": false,
          "age_appearance": "apparent age description",
          "height": "height description",
          "build": "body build description"
        },
        "hair_details": {
          "changed": false,
          "length": "hair length",
          "color": "hair color",
          "style": "current hairstyle",
          "texture": "hair texture if notable"
        },
        "eye_details": {
          "changed": false,
          "color": "eye color",
          "shape": "eye shape if distinctive",
          "expression": "current eye expression"
        },
        "body_details": {
          "changed": false,
          "body_type": "body type description",
          "skin_tone": "skin tone description",
          "notable_features": "any notable physical features"
        },
        "distinctive_features": {
          "changed": false,
          "permanent": ["list of permanent distinctive features"],
          "temporary": ["list of temporary marks or features"]
        },
        "current_expression": {
          "changed": false,
          "primary_emotion": "main emotion",
          "intensity": 1-10,
          "facial_expression": "detailed facial expression",
          "mood_description": "overall mood description"
        },
        "clothing": {
          "changed": false,
          "outfit_type": "type of outfit",
          "top": "top garment description",
          "bottom": "bottom garment description",
          "accessories": ["list of accessories"],
          "style": "overall clothing style",
          "condition": "clothing condition (neat, disheveled, etc.)"
        },
        "pose_activity": {
          "changed": false,
          "current_pose": "body position description",
          "activity": "what they're currently doing",
          "body_language": "body language indicators",
          "hand_position": "hand/arm positioning"
        },
        "location_environment": {
          "changed": false,
          "setting": "current location/setting",
          "environment_type": "indoor/outdoor/specific type",
          "lighting": "lighting conditions",
          "atmosphere": "atmospheric description",
          "background_elements": ["notable background elements"]
        },
        "injuries": {
          "changed": false,
          "has_injuries": true/false,
          "injury_list": ["list of current injuries if any"],
          "severity": "injury severity if applicable"
        },
        "follow_up": {
          "has_intent": true/false,
          "reason": "why a follow-up is expected",
          "estimated_delay_minutes": 1-30,
          "context": "what the character said they would do"
        },
        "analysis_meta": {
          "changes_detected": ["list of what changed from previous state"],
          "mood_intensity": 1-10,
          "context_significance": 1-10,
          "visual_update_needed": true/false,
          "consistency_notes": "notes about maintaining visual consistency"
        }
      }

      IMPORTANT: Every field must be filled with appropriate data. Use current context or reasonable defaults if specific details aren't mentioned.
      Respond with ONLY the JSON, no additional text.
    PROMPT
  end

  def build_character_context(current_state)
    if current_state
      <<~CONTEXT
        Current Location: #{current_state.location || "Unknown"}
        Current Expression: #{current_state.expression || "Neutral"}
        Current Clothing: #{format_clothing_details(current_state.clothing_details)}
        Current Appearance: #{current_state.appearance_description}
        Recent Injuries: #{format_injury_details(current_state.injury_details)}
      CONTEXT
    else
      <<~CONTEXT
        Character: #{@character.name}
        Base Description: #{@character.description}
        Current State: Initial conversation - no previous state
      CONTEXT
    end
  end

  def format_clothing_details(clothing_details)
    return "Default outfit" unless clothing_details.present?

    if clothing_details["latest_change"]
      clothing_details["latest_change"]
    else
      "Default outfit"
    end
  end

  def format_injury_details(injury_details)
    return "None" unless injury_details.present?

    if injury_details["latest_injury"]
      injury_details["latest_injury"]
    else
      "None"
    end
  end

  def request_context_analysis(prompt)
    begin
      # Ensure the context analyzer character exists
      analyzer_character = ContextAnalyzerCharacterService.get_context_analyzer_character
      unless analyzer_character
        Rails.logger.error "Context analyzer character not available"
        return fallback_analysis(prompt)
      end

      response = @venice_client.create_chat_completion(
        body: {
          model: "venice-uncensored",
          messages: [
            { role: "system", content: Character.find_by(slug: ContextAnalyzerCharacterService::CONTEXT_ANALYZER_SLUG).description },
            { role: "user", content: prompt },
          ],
        },
      )
      response.choices.first[:message][:content] || ""
    rescue => e
      Rails.logger.error "AI Context Analysis failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Fallback to basic analysis if AI fails
      fallback_analysis(prompt)
    end
  end

  def parse_ai_response(ai_response)
    begin
      # Extract JSON from response (in case there's extra text)
      json_match = ai_response.match(/\{.*\}/m)
      json_string = json_match ? json_match[0] : ai_response

      parsed = JSON.parse(json_string)

      # Validate and normalize the response structure
      normalize_ai_response(parsed)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse AI response as JSON: #{e.message}"
      Rails.logger.error "AI Response: #{ai_response}"

      # Return empty changes if parsing fails
      default_empty_response
    end
  end

  def normalize_ai_response(parsed)
    {
      # Complete character details (always present)
      physical_features: extract_physical_features(parsed),
      hair_details: extract_hair_details(parsed),
      eye_details: extract_eye_details(parsed),
      body_details: extract_body_details(parsed),
      distinctive_features: extract_distinctive_features(parsed),
      current_expression: extract_current_expression(parsed),
      clothing: extract_clothing_details(parsed),
      pose_activity: extract_pose_activity(parsed),
      location_environment: extract_location_environment(parsed),
      injuries: extract_injuries(parsed),
      
      # Legacy fields for backward compatibility
      location_change: extract_location_change_legacy(parsed),
      expression_change: extract_expression_change_legacy(parsed),
      clothing_change: extract_clothing_change_legacy(parsed),
      appearance_change: extract_appearance_change_legacy(parsed),
      pose_change: extract_pose_change_legacy(parsed),
      
      # Analysis metadata
      mood_intensity: parsed.dig("analysis_meta", "mood_intensity") || 5,
      context_significance: parsed.dig("analysis_meta", "context_significance") || 1,
      visual_update_needed: parsed.dig("analysis_meta", "visual_update_needed") || false,
      changes_detected: parsed.dig("analysis_meta", "changes_detected") || [],
      consistency_notes: parsed.dig("analysis_meta", "consistency_notes") || "",
      follow_up_intent: extract_follow_up_intent(parsed),
      raw_analysis: parsed,
    }
  end

  def extract_physical_features(parsed)
    parsed["physical_features"] || {}
  end

  def extract_hair_details(parsed)
    parsed["hair_details"] || {}
  end

  def extract_eye_details(parsed)
    parsed["eye_details"] || {}
  end

  def extract_body_details(parsed)
    parsed["body_details"] || {}
  end

  def extract_distinctive_features(parsed)
    parsed["distinctive_features"] || {}
  end

  def extract_current_expression(parsed)
    parsed["current_expression"] || {}
  end

  def extract_clothing_details(parsed)
    parsed["clothing"] || {}
  end

  def extract_pose_activity(parsed)
    parsed["pose_activity"] || {}
  end

  def extract_location_environment(parsed)
    parsed["location_environment"] || {}
  end

  def extract_injuries(parsed)
    parsed["injuries"] || {}
  end

  def extract_location_change_legacy(parsed)
    # Try new format first, then fall back to old format
    if parsed["location_environment"] && parsed["analysis_meta"] && parsed["analysis_meta"]["changes_detected"]
      changes = parsed["analysis_meta"]["changes_detected"]
      return parsed["location_environment"]["setting"] if changes.any? { |c| c.downcase.include?("location") || c.downcase.include?("environment") }
    end
    
    # Old format fallback
    location_data = parsed["location"]
    return nil unless location_data && location_data["changed"]
    location_data["new_location"]
  end

  def extract_expression_change_legacy(parsed)
    # Try new format first
    if parsed["current_expression"] && parsed["analysis_meta"] && parsed["analysis_meta"]["changes_detected"]
      changes = parsed["analysis_meta"]["changes_detected"]
      if changes.any? { |c| c.downcase.include?("expression") || c.downcase.include?("emotion") }
        expr = parsed["current_expression"]
        parts = []
        parts << expr["primary_emotion"] if expr["primary_emotion"]
        parts << "intensity #{expr["intensity"]}" if expr["intensity"]
        parts << expr["facial_expression"] if expr["facial_expression"]
        return parts.any? ? parts.join(", ") : nil
      end
    end
    
    # Old format fallback
    expression_data = parsed["expression"]
    return nil unless expression_data&.dig("changed")

    emotion = expression_data["emotion"]
    intensity = expression_data["intensity"] || 5
    description = expression_data["description"]

    # Combine emotion with intensity for richer expression
    if description.present?
      description
    elsif intensity > 7
      "very #{emotion}"
    elsif intensity < 3
      "slightly #{emotion}"
    else
      emotion
    end
  end

  def extract_expression_change(parsed)
    extract_expression_change_legacy(parsed)
  end

  def extract_clothing_change_legacy(parsed)
    # Try new format first
    if parsed["clothing"] && parsed["analysis_meta"] && parsed["analysis_meta"]["changes_detected"]
      changes = parsed["analysis_meta"]["changes_detected"]
      if changes.any? { |c| c.downcase.include?("clothing") || c.downcase.include?("outfit") }
        clothing = parsed["clothing"]
        parts = []
        parts << clothing["outfit_type"] if clothing["outfit_type"]
        parts << clothing["top"] if clothing["top"]
        parts << clothing["bottom"] if clothing["bottom"]
        return parts.any? ? parts.join(", ") : nil
      end
    end
    
    # Old format fallback
    clothing_data = parsed["clothing"]
    return nil unless clothing_data&.dig("changed")
    clothing_data["description"] || clothing_data["style"]
  end

  def extract_clothing_change(parsed)
    extract_clothing_change_legacy(parsed)
  end

  def extract_appearance_change_legacy(parsed)
    # Try new format first
    if parsed["analysis_meta"] && parsed["analysis_meta"]["changes_detected"]
      changes = parsed["analysis_meta"]["changes_detected"]
      appearance_changes = changes.select { |c| c.downcase.include?("appearance") || c.downcase.include?("hair") || c.downcase.include?("physical") }
      return appearance_changes.join(", ") if appearance_changes.any?
    end
    
    # Old format fallback
    appearance_data = parsed["appearance"]
    return nil unless appearance_data&.dig("changed")
    changes = appearance_data["changes"]
    return nil unless changes&.any?
    changes.join(", ")
  end

  def extract_appearance_change(parsed)
    extract_appearance_change_legacy(parsed)
  end

  def extract_pose_change_legacy(parsed)
    # Try new format first
    if parsed["pose_activity"] && parsed["analysis_meta"] && parsed["analysis_meta"]["changes_detected"]
      changes = parsed["analysis_meta"]["changes_detected"]
      if changes.any? { |c| c.downcase.include?("pose") || c.downcase.include?("activity") || c.downcase.include?("position") }
        pose = parsed["pose_activity"]
        parts = []
        parts << pose["current_pose"] if pose["current_pose"]
        parts << pose["activity"] if pose["activity"]
        parts << pose["body_language"] if pose["body_language"]
        return parts.any? ? parts.join(", ") : nil
      end
    end
    
    # Old format fallback
    pose_data = parsed["pose"]
    return nil unless pose_data&.dig("changed")
    description = pose_data["description"]
    body_language = pose_data["body_language"]
    [description, body_language].compact.join(", ")
  end

  def extract_pose_change(parsed)
    extract_pose_change_legacy(parsed)
  end

  def extract_follow_up_intent(parsed)
    follow_up_data = parsed["follow_up"]
    return nil unless follow_up_data&.dig("has_intent")

    {
      has_intent: true,
      reason: follow_up_data["reason"],
      estimated_delay_minutes: follow_up_data["estimated_delay_minutes"] || 5,
      context: follow_up_data["context"]
    }
  end

  # Helper methods to extract specific data from comprehensive format with change detection
  def extract_location_from_comprehensive_data(context_changes)
    location_env = context_changes[:location_environment]
    return nil unless location_env && location_env["changed"]
    
    location_env["current_location"] || location_env["environment"] || location_env["setting"]
  end

  def extract_expression_from_comprehensive_data(context_changes)
    expression = context_changes[:current_expression]
    return nil unless expression && expression["changed"]
    
    parts = []
    parts << expression["primary_emotion"] if expression["primary_emotion"]
    parts << "(#{expression['intensity']}/10)" if expression["intensity"]
    parts.any? ? parts.join(" ") : nil
  end

  def extract_body_type_from_comprehensive_data(context_changes)
    # Check both body_details and physical_features for body type info
    body = context_changes[:body_details] || context_changes[:physical_features]
    return nil unless body && body["changed"]
    
    body["body_type"] || body["build"]
  end

  def extract_skin_tone_from_comprehensive_data(context_changes)
    body = context_changes[:body_details] || context_changes[:physical_features]
    return nil unless body && body["changed"]
    
    body["skin_tone"]
  end

  def extract_pose_from_comprehensive_data(context_changes)
    pose_activity = context_changes[:pose_activity]
    return nil unless pose_activity && pose_activity["changed"]
    
    parts = []
    parts << pose_activity["current_pose"] if pose_activity["current_pose"]
    parts << pose_activity["activity"] if pose_activity["activity"]
    parts.any? ? parts.join(", ") : nil
  end

  # Methods to get complete data (for initial state or when needed regardless of changes)
  def get_complete_location_data(context_changes)
    location_env = context_changes[:location_environment]
    return nil unless location_env
    
    location_env["current_location"] || location_env["environment"] || location_env["setting"]
  end

  def get_complete_expression_data(context_changes)
    expression = context_changes[:current_expression]
    return nil unless expression
    
    parts = []
    parts << expression["primary_emotion"] if expression["primary_emotion"]
    parts << "(#{expression['intensity']}/10)" if expression["intensity"]
    parts.any? ? parts.join(" ") : nil
  end

  def get_complete_physical_features(context_changes)
    context_changes[:physical_features] || {}
  end

  def get_complete_hair_details(context_changes)
    context_changes[:hair_details] || {}
  end

  def get_complete_eye_details(context_changes)
    context_changes[:eye_details] || {}
  end

  def get_complete_distinctive_features(context_changes)
    context_changes[:distinctive_features] || {}
  end

  # Helper method to get changed data or complete data based on initial state
  def get_changed_or_complete_data(new_data, previous_data, is_initial_state)
    if is_initial_state
      # For initial state, always use complete data from AI analysis
      new_data || {}
    else
      # For subsequent states, only use new data if it has changed
      if new_data && new_data["changed"]
        new_data
      else
        previous_data || {}
      end
    end
  end

  # Build unified state data from AI analysis with change detection
  def build_unified_state_data(context_changes, previous_state, is_initial_state)
    previous_data = previous_state&.state_data || {}
    
    {
      # Basic state fields
      'location' => extract_location_from_comprehensive_data(context_changes) || 
                    (is_initial_state ? get_complete_location_data(context_changes) : previous_data['location']),
      'expression' => extract_expression_from_comprehensive_data(context_changes) || 
                      (is_initial_state ? get_complete_expression_data(context_changes) : previous_data['expression']),
      
      # Comprehensive appearance data
      'appearance_description' => build_comprehensive_appearance_description(context_changes, previous_state, is_initial_state),
      'clothing_details' => build_comprehensive_clothing_details(context_changes, previous_state, is_initial_state),
      'injury_details' => build_comprehensive_injury_details(context_changes, previous_state, is_initial_state),
      'background_prompt' => build_comprehensive_background_prompt(context_changes, previous_state, is_initial_state),
      
      # Detailed character features with change detection
      'physical_features' => get_changed_or_complete_data(context_changes[:physical_features], previous_data['physical_features'], is_initial_state),
      'hair_details' => get_changed_or_complete_data(context_changes[:hair_details], previous_data['hair_details'], is_initial_state),
      'eye_details' => get_changed_or_complete_data(context_changes[:eye_details], previous_data['eye_details'], is_initial_state),
      'distinctive_features' => get_changed_or_complete_data(context_changes[:distinctive_features], previous_data['distinctive_features'], is_initial_state),
      'default_outfit' => get_changed_or_complete_data(context_changes[:clothing], previous_data['default_outfit'], is_initial_state),
      
      # Extracted single-value fields
      'body_type' => extract_body_type_from_comprehensive_data(context_changes) || 
                     (is_initial_state ? extract_body_type_from_complete_data(context_changes) : previous_data['body_type']),
      'skin_tone' => extract_skin_tone_from_comprehensive_data(context_changes) || 
                     (is_initial_state ? extract_skin_tone_from_complete_data(context_changes) : previous_data['skin_tone']),
      'pose_style' => extract_pose_from_comprehensive_data(context_changes) || 
                      (is_initial_state ? extract_pose_from_complete_data(context_changes) : previous_data['pose_style']),
      
      # Background and environment details
      'detailed_background_info' => get_changed_or_complete_data(context_changes[:location_environment], previous_data['detailed_background_info'], is_initial_state),
      
      # Character prompt data
      'base_character_prompt' => previous_data['base_character_prompt'], # Preserve existing prompt
      'art_style_notes' => previous_data['art_style_notes'] # Preserve existing style notes
    }.compact # Remove nil values
  end

  # Methods to extract data from complete format (ignoring changed flag)
  def extract_body_type_from_complete_data(context_changes)
    body = context_changes[:body_details] || context_changes[:physical_features]
    return nil unless body
    
    body["body_type"] || body["build"]
  end

  def extract_skin_tone_from_complete_data(context_changes)
    body = context_changes[:body_details] || context_changes[:physical_features]
    return nil unless body
    
    body["skin_tone"]
  end

  def extract_pose_from_complete_data(context_changes)
    pose_activity = context_changes[:pose_activity]
    return nil unless pose_activity
    
    parts = []
    parts << pose_activity["current_pose"] if pose_activity["current_pose"]
    parts << pose_activity["activity"] if pose_activity["activity"]
    parts.any? ? parts.join(", ") : nil
  end

  # Simplified builder methods for unified state data
  def build_comprehensive_appearance_description(context_changes, previous_state, is_initial_state = false)
    # Combine all appearance elements into a cohesive description
    parts = []
    
    # Use physical features if changed or if initial state
    phys_features = context_changes[:physical_features]
    if phys_features && (is_initial_state || phys_features["changed"])
      parts << phys_features["face_shape"] if phys_features["face_shape"]
      parts << phys_features["height"] if phys_features["height"]
    end
    
    # Use hair details if changed or if initial state
    hair_details = context_changes[:hair_details]
    if hair_details && (is_initial_state || hair_details["changed"])
      hair_desc = [hair_details["color"], hair_details["style"], hair_details["length"]].compact.join(" ")
      parts << "#{hair_desc} hair" if hair_desc.present?
    end
    
    # Use eye details if changed or if initial state
    eye_details = context_changes[:eye_details]
    if eye_details && (is_initial_state || eye_details["changed"])
      eye_desc = [eye_details["color"], eye_details["shape"]].compact.join(" ")
      parts << "#{eye_desc} eyes" if eye_desc.present?
    end
    
    description = parts.any? ? parts.join(', ') : nil
    description || previous_state&.appearance_description || ""
  end

  def build_comprehensive_clothing_details(context_changes, previous_state, is_initial_state = false)
    clothing = context_changes[:clothing]
    
    # Return previous state if no clothing data or no changes (unless initial state)
    return previous_state&.clothing_details || {} unless clothing && (is_initial_state || clothing["changed"])
    
    # Merge with previous clothing details, keeping latest changes
    previous_clothing = previous_state&.clothing_details || {}
    previous_clothing.merge({
      "latest_change" => [clothing["top"], clothing["bottom"], clothing["accessories"]].compact.join(", "),
      "outfit_type" => clothing["outfit_type"],
      "style" => clothing["style"]
    }.compact)
  end

  def build_comprehensive_injury_details(context_changes, previous_state, is_initial_state = false)
    injuries = context_changes[:injuries]
    
    # Return previous state if no injury data or no changes (unless initial state)
    return previous_state&.injury_details || {} unless injuries && (is_initial_state || injuries["changed"])
    
    # Merge with previous injury details
    previous_injuries = previous_state&.injury_details || {}
    if injuries["visible_injuries"] && injuries["visible_injuries"].any?
      previous_injuries.merge({
        "latest_injury" => injuries["visible_injuries"].join(", "),
        "severity" => injuries["severity"]
      })
    else
      previous_injuries
    end
  end

  def build_comprehensive_background_prompt(context_changes, previous_state, is_initial_state = false)
    location_env = context_changes[:location_environment]
    
    # Return previous state if no location data or no changes (unless initial state)
    return previous_state&.background_prompt || "" unless location_env && (is_initial_state || location_env["changed"])
    
    parts = []
    parts << location_env["environment"] if location_env["environment"]
    parts << location_env["setting"] if location_env["setting"]
    parts << location_env["lighting"] if location_env["lighting"]
    parts << location_env["atmosphere"] if location_env["atmosphere"]
    
    parts.any? ? parts.join(", ") : (previous_state&.background_prompt || "")
  end

  def default_empty_response
    {
      location_change: nil,
      expression_change: nil,
      clothing_change: nil,
      appearance_change: nil,
      pose_change: nil,
      mood_intensity: 5,
      context_significance: 1,
      visual_update_needed: false,
      summary: "",
      raw_analysis: {},
    }
  end

  def fallback_analysis(original_prompt)
    # Simple keyword-based fallback if AI analysis fails
    message_lower = original_prompt.downcase

    fallback_response = {
      "location" => { "changed" => false },
      "expression" => { "changed" => detect_emotion_keywords(message_lower) },
      "clothing" => { "changed" => detect_clothing_keywords(message_lower) },
      "appearance" => { "changed" => false },
      "pose" => { "changed" => false },
      "overall" => {
        "mood_intensity" => 5,
        "context_significance" => 3,
        "visual_update_needed" => false,
        "summary" => "Fallback analysis used",
      },
    }

    JSON.generate(fallback_response)
  end

  def detect_emotion_keywords(text)
    emotions = %w[happy sad angry excited worried surprised confused scared]
    emotions.any? { |emotion| text.include?(emotion) }
  end

  def detect_clothing_keywords(text)
    clothing_words = %w[wear wearing dress outfit clothes shirt pants]
    clothing_words.any? { |word| text.include?(word) }
  end

  def create_character_state_if_needed(context_changes, message_content, role, ai_response)
    # Only create new state if AI determined visual update is needed or significance is high
    return @conversation.current_character_state unless should_create_new_state?(context_changes)

    previous_state = @conversation.current_character_state

    # Determine if this is the first state (no previous state exists)
    is_initial_state = previous_state.nil?
    
    # Build unified state data from AI analysis with change detection
    unified_data = build_unified_state_data(context_changes, previous_state, is_initial_state)
  
    new_state = @conversation.character_states.build(
      unified_state_data: unified_data,
      message_context: message_content,
      triggered_by_role: role,
      ai_analysis_summary: context_changes[:consistency_notes] || context_changes[:summary] || "",
      mood_intensity: context_changes[:mood_intensity],
      context_significance: context_changes[:context_significance],
    )

    # Initialize detailed character description for consistent image generation
    new_state.initialize_base_character_description(@conversation.character)

    # Initialize detailed background description for consistent scene generation
    new_state.initialize_detailed_background_description

    # Save the new state
    new_state.save

    Rails.logger.info "Scene regeneration needed due to: #{[
                        context_changes[:appearance_change] ? "appearance #{context_changes[:appearance_change]}" : nil,
                        context_changes[:clothing_change] ? "clothing #{context_changes[:clothing_change]}" : nil,
                        context_changes[:expression_change] ? "expression #{context_changes[:expression_change]}" : nil,
                        context_changes[:location_change] ? "location #{context_changes[:location_change]}" : nil,
                        (context_changes[:context_significance] && context_changes[:context_significance] >= 7) ? "high_significance #{context_changes[:context_significance]}" : nil,
                      ].compact.join(", ")}"

    new_state
  end

  def should_create_new_state?(context_changes)
    # Create new state if:
    # 1. AI explicitly says visual update is needed
    # 2. Context significance is high (7+)
    # 3. Any major changes detected
    context_changes[:visual_update_needed] ||
      context_changes[:context_significance] >= 7 ||
      has_significant_changes?(context_changes)
  end

  def has_significant_changes?(context_changes)
    [
      context_changes[:location_change],
      context_changes[:expression_change],
      context_changes[:clothing_change],
      context_changes[:appearance_change],
    ].any?(&:present?)
  end

  def build_appearance_description(context_changes, previous_state)
    base_description = previous_state&.appearance_description || @character.description || "A character"

    if context_changes[:appearance_change]
      "#{base_description}. #{context_changes[:appearance_change]}"
    else
      base_description
    end
  end

  def build_clothing_details(context_changes, previous_state)
    details = previous_state&.clothing_details || {}

    if context_changes[:clothing_change]
      details.merge(
        latest_change: context_changes[:clothing_change],
        updated_at: Time.current,
        ai_detected: true,
      )
    else
      details
    end
  end

  def build_injury_details(context_changes, previous_state)
    details = previous_state&.injury_details || {}

    # Check if appearance change includes injury-related content
    if context_changes[:appearance_change]&.match?(/injur|hurt|wound|bleed|bruise|cut|scar/)
      details.merge(
        latest_injury: context_changes[:appearance_change],
        updated_at: Time.current,
        ai_detected: true,
      )
    else
      details
    end
  end

  def build_background_prompt(context_changes, previous_state)
    if context_changes[:location_change]
      "Visual novel style background of #{context_changes[:location_change]}, detailed and atmospheric"
    else
      previous_state&.background_prompt || "A cozy indoor setting with warm lighting"
    end
  end
end
