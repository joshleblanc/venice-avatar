module CharacterToolCalls
  extend ActiveSupport::Concern

  COMMON_RULES = <<~COMMON_RULES
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
          description: "Update the adult character's CURRENT appearance as structured JSON. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              appearance: {
                type: "object",
                description: <<~DESC,
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of the ADULT character's CURRENT appearance
                  as a structured JSON object. This fully replaces any previous appearance, so you MUST
                  include all established details that still apply.

                  The appearance should reflect the character's current state.

                  RULES:
                  - Third person only (“she”, “they”, “the character”), no names.
                  - No first/second person, no emotions, no personality, no story.
                  - Do NOT describe pose or location here; only how the character looks.
                  - If a detail was established before and not changed, repeat it here.
                DESC
                properties: {
                  height: {
                    type: "string",
                    description: "Approximate height, e.g., 'tall', 'average height', 'short'."
                  },
                  build: {
                    type: "string",
                    description: "Overall build and body type, e.g., 'slender, statuesque, hourglass proportions'."
                  },
                  proportions: {
                    type: "string",
                    description: "Body proportions and notable physical emphasis, e.g., 'long legs, large bust, narrow waist'."
                  },
                  skin: {
                    type: "string",
                    description: "Skin tone and visible characteristics, e.g., 'smooth synthetic skin with a subtle artificial sheen'."
                  },
                  hair: {
                    type: "string",
                    description: "Hair color, length, texture, and style, e.g., 'long golden hair flowing past the waist, straight and glossy'."
                  },
                  eyes: {
                    type: "string",
                    description: "Eye color and outward look, e.g., 'bright shimmering eyes, softly focused forward'."
                  },
                  face: {
                    type: "string",
                    description: "Facial structure and notable features, and visible makeup if any."
                  },
                  clothing: {
                    type: "string",
                    description: <<~CLO
                      Full outfit description with garments, colors, materials, fit, and coverage.
                      Example: "form-fitting knee-length white satin dress with thin straps, closely hugging the torso and hips".
                      If no clothing is present, then the character is naked.
                    CLO
                  },
                  accessories: {
                    type: "string",
                    description: "All visible jewelry, glasses, devices, etc., or 'none' if there are no accessories."
                  },
                  distinctive: {
                    type: "string",
                    description: "Any distinctive visual features (e.g., tattoos, scars, glowing elements), or 'none'."
                  }
                },
                required: [
                  "height",
                  "build",
                  "proportions",
                  "skin",
                  "hair",
                  "eyes",
                  "face",
                  "clothing",
                  "accessories",
                  "distinctive"
                ]
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
          description: "Update the adult character's CURRENT location as structured JSON. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              location: {
                type: "object",
                description: <<~DESC,
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of the CURRENT environment
                  as a structured JSON object. This fully replaces any previous location, so you MUST
                  include all established visual details that still apply.

                  RULES:
                  - Describe only the visible environment around the character.
                  - No first/second person, no names, no emotions, no story.
                  - Do NOT describe the character's pose or appearance here.
                DESC
                properties: {
                  space_type: {
                    type: "string",
                    description: "Type of space, e.g., 'luxurious modern living room', 'bedroom', 'office'."
                  },
                  overall_style: {
                    type: "string",
                    description: "Overall visual style, e.g., 'minimalist', 'high-tech', 'cozy', 'opulent'."
                  },
                  key_furniture: {
                    type: "string",
                    description: "Main furniture pieces near or relevant to the character, e.g., 'navy velvet couch, glass coffee table, low media console'."
                  },
                  key_objects: {
                    type: "string",
                    description: "Notable objects in the scene, e.g., 'coffee carafe and two mugs, smart speakers, decorative plants'."
                  },
                  materials_colors: {
                    type: "string",
                    description: "Dominant materials and colors, e.g., 'polished stone floor, warm neutral walls, metallic accents'."
                  },
                  lighting: {
                    type: "string",
                    description: "Lighting type, direction, and feel, e.g., 'warm evening light from large windows with soft ambient lamps'."
                  },
                  background_elements: {
                    type: "string",
                    description: "Visible background elements, e.g., 'city lights through window, wall-mounted screen, shelving'."
                  },
                  atmosphere_physical: {
                    type: "string",
                    description: "Purely physical ambient details, e.g., 'faint steam from coffee, soft hum of automation systems'. No emotions."
                  },
                  layout_notes: {
                    type: "string",
                    description: "Brief notes on layout relative to the character, e.g., 'couch facing window, coffee table in front of couch'."
                  }
                },
                required: [
                  "space_type",
                  "overall_style",
                  "key_furniture",
                  "key_objects",
                  "materials_colors",
                  "lighting",
                  "background_elements",
                  "atmosphere_physical",
                  "layout_notes"
                ]
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
          description: "Update the adult character's CURRENT pose and action as structured JSON. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              action: {
                type: "object",
                description: <<~DESC,
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of what the ADULT character is CURRENTLY doing,
                  as a structured JSON object. This fully replaces any previous action, so you MUST include the
                  actual current pose and interactions.

                  RULES:
                  - Third person only, no names, no first/second person.
                  - No emotions, no motivations, no inner thoughts.
                  - Describe ONLY physical pose, movement, and interactions with visible objects.
                DESC
                properties: {
                  body_position: {
                    type: "string",
                    description: "Overall body position, e.g., 'standing upright', 'sitting on couch', 'reclining on side'."
                  },
                  torso_orientation: {
                    type: "string",
                    description: "Orientation of torso relative to the environment, e.g., 'torso facing forward toward the door'."
                  },
                  leg_position: {
                    type: "string",
                    description: "Position and stance of legs and feet, e.g., 'legs close together, feet shoulder-width apart, weight evenly distributed'."
                  },
                  arm_position: {
                    type: "string",
                    description: "General placement of arms, e.g., 'arms hanging naturally at sides', 'one arm resting on back of couch'."
                  },
                  hand_details: {
                    type: "string",
                    description: "Specific hand positions and interactions, e.g., 'right hand lightly touching the back of the couch, left hand relaxed at side'."
                  },
                  head_gaze: {
                    type: "string",
                    description: "Head orientation and gaze direction, e.g., 'head slightly tilted, eyes looking toward the entrance'."
                  },
                  interaction: {
                    type: "string",
                    description: "What the character is interacting with, if anything, e.g., 'reaching toward the coffee table', or 'no direct interaction'."
                  },
                  motion: {
                    type: "string",
                    description: "Whether the pose is static or moving, and if moving, how, e.g., 'static', 'beginning to step forward with smooth, measured steps'."
                  },
                  notes: {
                    type: "string",
                    description: "Any additional neutral physical details about the pose/action, or 'none'."
                  }
                },
                required: [
                  "body_position",
                  "torso_orientation",
                  "leg_position",
                  "arm_position",
                  "hand_details",
                  "head_gaze",
                  "interaction",
                  "motion",
                  "notes"
                ]
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
