module CharacterToolCalls
  extend ActiveSupport::Concern

  COMMON_RULES = <<~COMMON_RULES
  <<~INSTRUCTIONS
  RULES:
  - ALWAYS use third-person
  - NEVER include the character’s name or invent one
  - NO first- or second-person language
  - NO emotions, “vibes,” or metaphorical atmospheres
  - ONLY describe what is visually present
  - ONLY update the location if movement is explicitly mentioned
  COMMON_RULES

  # Tool definitions for character appearance and location updates
  def character_tools
    [
      {
        type: "function",
        function: {
          name: "update_appearance",
          description: "Provide a COMPLETE, third-person, purely visual description of the adult character's CURRENT appearance. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              appearance: {
                type: "string",
                description: <<~DESC                  
  A COMPLETE, NEUTRAL, THIRD-PERSON description of the ADULT character's CURRENT appearance.

  This is the SINGLE SOURCE OF TRUTH for appearance and FULLY REPLACES any previous appearance.

  INCLUDE, IN MAXIMUM VISUAL DETAIL:
  - Height, build, body type, proportions
  - Skin tone and distinctive visible features (scars, tattoos, etc.)
  - Hair: exact color, length, texture, style
  - Eyes: color and general look (neutral / focused / relaxed – but not emotions)
  - Face: key features, makeup if present
  - Clothing: full outfit with colors, materials, fit. If no clothing, explicitly state that.
  - Accessories: all visible jewelry, glasses, devices, etc.

  HARD RULES:
  - Do NOT mention pose, stance, or how the character is positioned (standing/sitting/reclining).
  - Do NOT describe the surrounding environment or location.
  - ALWAYS third person.
  - NEVER include the character's name, or use first/second person, or describe emotions/personality.

  If a detail was established before and not changed, you MUST repeat it here.
  Output one cohesive third-person appearance description.
DESC
              }
            },
            required: ["appearance"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "update_location",
          description: "Provide a COMPLETE, third-person, purely visual description of the adult character's CURRENT location. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              location: {
                type: "string",
                description: <<~DESC
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of the CURRENT environment, including:

                  - Type of space (e.g., living room, bedroom, office, terrace)
                  - Visible furniture, objects, surfaces, and materials
                  - Architectural details: windows, floors, walls, layout
                  - Lighting conditions: natural or artificial, brightness, direction
                  - Colors and textures in the environment
                  - Decorative or notable visible elements
                  - Ambient *physical* details only (e.g., visible steam, displayed screens)

                  #{COMMON_RULES}

                  Output must be a single cohesive third-person location description.
                DESC
              }
            },
            required: ["location"]
          }
        }
      },
      {
        type: "function",
        function: {
          name: "update_action",
          description: "Provide a COMPLETE, third-person, purely visual description of the adult character's CURRENT action and how they are posed. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              action: {
                type: "string",                
                description: <<~DESC
  A COMPLETE, NEUTRAL, THIRD-PERSON description of what the ADULT character is CURRENTLY doing and how they are posed.

  This is the SINGLE SOURCE OF TRUTH for pose and action and FULLY REPLACES any previous action.

  YOU MUST EXPLICITLY DESCRIBE:
  - Body position: standing, sitting upright, kneeling, reclining, lying on side, etc.
  - Torso orientation: straight, leaning forward/backward, twisted left/right.
  - Leg position: apart or together, bent or straight, on floor / couch / other surface.
  - Arm and hand position: what each arm is doing; where each hand rests or what it holds/touches.
  - Head and gaze: head tilt and where the eyes are looking.
  - Interaction with objects: any furniture or objects being touched, leaned on, or held.
  - Whether the pose is static or in motion.

  HARD RULES:
  - ALWAYS third person.
  - NEVER include the character's name or use first/second person.
  - Do NOT describe thoughts, emotions, or reasons—only physical pose and action.
  - Do NOT use vague phrases like "relaxed pose", "comfortable stance", or "natural position" without specifying exact limb positions.
  - If the character is simply standing neutrally, explicitly describe: feet position, leg stance, arms at sides or folded, etc.

  If the conversation did NOT change the pose, restate the existing pose in full detail.
  Output one cohesive third-person action description.
DESC
              }
            },
            required: ["action"]
          }
        }
      }

    ]
  end

  # Process tool calls and update conversation state
  def process_character_tool_calls(conversation, tool_calls)
    return unless tool_calls.present?

    tool_calls.each do |tool_call|
      tool_name = tool_call[:function][:name]
      arguments = parse_tool_arguments(tool_call[:function][:arguments])

      Rails.logger.debug "Processing tool call: #{tool_name} with arguments: #{arguments.inspect}"

      case tool_name
      when "update_appearance"
        conversation.appearance = arguments["appearance"]
      when "update_location"
        conversation.location = arguments["location"]
      when "update_action"
        conversation.action = arguments["action"]
      end
    end

    conversation.save! if conversation.changed?
    Rails.logger.info "Character state updated, triggering background image generation"
    GenerateImagesJob.perform_later(conversation)
  end

  def parse_tool_arguments(arguments)
    parsed_arguments = arguments
    parsed_arguments = JSON.parse(parsed_arguments) if parsed_arguments.is_a?(String)
    parsed_arguments = JSON.parse(parsed_arguments) if parsed_arguments.is_a?(String)
    parsed_arguments
  rescue JSON::ParserError
    {}
  end

  def extract_tool_call_state(tool_calls)
    return {} unless tool_calls.present?

    state = {}

    tool_calls.each do |tool_call|
      tool_name = tool_call[:function][:name]
      arguments = parse_tool_arguments(tool_call[:function][:arguments])

      case tool_name
      when "update_appearance"
        state[:appearance] = arguments["appearance"]
      when "update_location"
        state[:location] = arguments["location"]
      when "update_action"
        state[:action] = arguments["action"]
      end
    end

    state
  end

  # Create message with both content and tool calls
  def create_message_with_tool_calls(conversation, response)
    if response.respond_to?(:tool_calls) && response.tool_calls.present?
      # Process tool calls first
      process_character_tool_calls(conversation, response.tool_calls)

      # Ensure we have content - generate fallback if needed
      content = response.content&.strip
      if content.blank?
        Rails.logger.error "⚠️  MISSING CONTENT: Response had #{response.tool_calls.length} tool calls but NO conversational content!"
        Rails.logger.error "Tool calls: #{response.tool_calls.map { |tc| tc[:function][:name] }.join(', ')}"
        Rails.logger.error "Generating fallback content to ensure user receives a response"
        content = generate_fallback_content(conversation, response.tool_calls)
      else
        Rails.logger.info "✓ Response includes both content and #{response.tool_calls.length} tool calls"
      end

      # Create message with both content and tool calls
      Rails.logger.info "Saving message with content: '#{content[0..100]}...' and #{response.tool_calls.length} tool calls"
      conversation.messages.create!(
        content: content,
        tool_calls: response.tool_calls,
        role: "assistant",
        user: conversation.user
      )
    elsif response.content.present?
      # Create message with content only
      conversation.messages.create!(
        content: response.content&.strip,
        role: "assistant",
        user: conversation.user
      )
    else
      # No content and no tool calls - this shouldn't happen, but handle it
      Rails.logger.error "Response had neither content nor tool calls, creating fallback message"
      conversation.messages.create!(
        content: "I'm here and ready to chat! How can I help you today?",
        role: "assistant",
        user: conversation.user
      )
    end
  end

  # Generate fallback content when response has tool calls but no conversational content
  #
  # @param [Conversation] conversation The conversation context
  # @param [Array] tool_calls The tool calls that were made
  # @return [String] Fallback conversational content
  def generate_fallback_content(conversation, tool_calls)
    # Get the last user message to understand context
    last_user_message = conversation.messages.where(role: "user").order(:created_at).last

    # If we have context from the user's message, try to be more responsive
    if last_user_message&.content.present?
      user_content = last_user_message.content.downcase

      # Try to match common conversational patterns
      if user_content.include?("hello") || user_content.include?("hi") || user_content.include?("hey")
        return "Hello! Nice to meet you. How are you doing today?"
      elsif user_content.include?("how are you") || user_content.include?("how's it going") || user_content.include?("how are u")
        return "I'm doing well, thank you for asking! How about you?"
      elsif user_content.include?("what") && (user_content.include?("doing") || user_content.include?("up"))
        return "I'm just here enjoying our conversation. What about you?"
      elsif user_content.include?("how") && user_content.include?("day")
        return "My day is going great, thanks for asking! How's yours been?"
      elsif user_content.include?("good morning")
        return "Good morning! How are you doing today?"
      elsif user_content.include?("good night") || user_content.include?("goodnight")
        return "Good night! Sleep well!"
      elsif user_content.include?("thank") || user_content.include?("thanks")
        return "You're very welcome! Is there anything else I can help you with?"
      elsif user_content.include?("?")
        # User asked a question but we don't have a specific response
        return "That's a great question! I'm here to chat about whatever's on your mind."
      end
    end

    # Generic fallback responses based on conversation state
    character_name = conversation.character.name || "I"

    generic_responses = [
      "I'm here and ready to chat! What's on your mind?",
      "How are you doing today?",
      "What would you like to talk about?",
      "I'm listening! Tell me more.",
      "Hey there! How can I help you today?",
      "I'm here for you. What's going on?",
      "Thanks for chatting with me! What would you like to know?"
    ]

    # Return a random generic response
    generic_responses.sample
  end

  # System prompt instructions for tool calls
  def tool_call_instructions
    
<<~INSTRUCTIONS
  TOOL CALL REQUIREMENTS (STATE MANAGER):

  You maintain three pieces of state:
  - appearance: what the adult character (18+) looks like
  - location: where the character is
  - action: what the character is physically doing / how they are posed

  GENERAL RULES:
  - ALWAYS write in third person (“the woman”, “she”, “they”, “the character”).
  - NEVER use first-person (“I”, “me”) or second-person (“you”) in tool outputs.
  - NEVER include the character’s name or invent one.
  - ADULT CONTENT ONLY: Never describe children, minors, or child-related content.
  - Each tool call is a FULL SNAPSHOT for that category and fully replaces the previous value.
  - If a detail was established earlier and not changed, you MUST repeat it.

  WHEN TO CALL TOOLS:
  - Call update_appearance when the conversation explicitly changes how the character looks
    (clothing, hair, accessories, visible body changes, makeup, etc.).
  - Call update_location when the conversation explicitly changes where the character is
    (moving to a different room/area, going outside, etc.).
  - Call update_action when the conversation explicitly or implicitly changes what the character is doing
    or how they are posed (standing vs sitting, lying down, crossing arms, etc.).
  - If nothing changed in a category, do NOT call that tool; the previous state remains.

  STATE CONSISTENCY RULES:
  - If clothing, hair color, body type, or accessories were not changed in the conversation, keep them the same and restate them.
  - If the room/location was not changed, keep the same room and restate it.
  - If pose or activity was not changed, keep the same pose/action and restate it.
  - Never introduce random changes (clothes, room, pose) without textual justification.

  APPEARANCE SNAPSHOT (NO POSE) – RULES:
  - Appearance describes the character’s body and outfit ONLY, not their actions or environment.
  - Do NOT describe detailed pose or position (no “standing comfortably”, “sitting on the couch” here).
  - Include ALL of:
  - height, build, body type, proportions
INSTRUCTIONS
  end
end
