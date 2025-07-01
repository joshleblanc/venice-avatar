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
    create_character_state_if_needed(context_changes, message_content, role, ai_response)
  end

  private

  def build_context_analysis_prompt(message_content, role, current_state)
    character_info = build_character_context(current_state)

    prompt = <<~PROMPT
      You are an expert at analyzing character interactions in visual novels. Analyze the following message for any changes to the character's state that would affect their visual representation.

      CHARACTER CONTEXT:
      #{character_info}

      MESSAGE TO ANALYZE:
      Role: #{role}
      Content: "#{message_content}"

      ANALYSIS INSTRUCTIONS:
      Analyze this message for changes in the following categories. For each category, determine if there's a change and provide specific details:

      1. LOCATION: Has the character moved to a new location or environment?
      2. EXPRESSION: What is the character's current emotional expression or mood?
      3. CLOTHING: Are there any changes to what the character is wearing?
      4. APPEARANCE: Any changes to physical appearance (hair, makeup, injuries, etc.)?
      5. POSE/ACTIVITY: What is the character doing or how are they positioned?
      6. MOOD_INTENSITY: Rate the emotional intensity from 1-10
      7. CONTEXT_SIGNIFICANCE: Rate how visually significant these changes are from 1-10

      RESPONSE FORMAT (JSON):
      {
        "location": {
          "changed": true/false,
          "new_location": "description of new location",
          "background_style": "visual novel background description"
        },
        "expression": {
          "changed": true/false,
          "emotion": "primary emotion",
          "intensity": 1-10,
          "description": "detailed expression description"
        },
        "clothing": {
          "changed": true/false,
          "description": "clothing change description",
          "style": "outfit style/type"
        },
        "appearance": {
          "changed": true/false,
          "changes": ["list of appearance changes"],
          "temporary": true/false
        },
        "pose": {
          "changed": true/false,
          "description": "pose/activity description",
          "body_language": "body language notes"
        },
        "overall": {
          "mood_intensity": 1-10,
          "context_significance": 1-10,
          "visual_update_needed": true/false,
          "summary": "brief summary of key changes"
        }
      }

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
      location_change: extract_location_change(parsed),
      expression_change: extract_expression_change(parsed),
      clothing_change: extract_clothing_change(parsed),
      appearance_change: extract_appearance_change(parsed),
      pose_change: extract_pose_change(parsed),
      mood_intensity: parsed.dig("overall", "mood_intensity") || 5,
      context_significance: parsed.dig("overall", "context_significance") || 1,
      visual_update_needed: parsed.dig("overall", "visual_update_needed") || false,
      summary: parsed.dig("overall", "summary") || "",
      raw_analysis: parsed,
    }
  end

  def extract_location_change(parsed)
    location_data = parsed["location"]
    return nil unless location_data&.dig("changed")

    location_data["new_location"]
  end

  def extract_expression_change(parsed)
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

  def extract_clothing_change(parsed)
    clothing_data = parsed["clothing"]
    return nil unless clothing_data&.dig("changed")

    clothing_data["description"] || clothing_data["style"]
  end

  def extract_appearance_change(parsed)
    appearance_data = parsed["appearance"]
    return nil unless appearance_data&.dig("changed")

    changes = appearance_data["changes"]
    return nil unless changes&.any?

    changes.join(", ")
  end

  def extract_pose_change(parsed)
    pose_data = parsed["pose"]
    return nil unless pose_data&.dig("changed")

    description = pose_data["description"]
    body_language = pose_data["body_language"]

    [description, body_language].compact.join(", ")
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

    new_state = @conversation.character_states.build(
      location: context_changes[:location_change] || previous_state&.location,
      appearance_description: build_appearance_description(context_changes, previous_state),
      expression: context_changes[:expression_change] || previous_state&.expression,
      clothing_details: build_clothing_details(context_changes, previous_state),
      injury_details: build_injury_details(context_changes, previous_state),
      background_prompt: build_background_prompt(context_changes, previous_state),
      message_context: message_content,
      triggered_by_role: role,
      # Store AI analysis metadata
      ai_analysis_summary: context_changes[:summary],
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
