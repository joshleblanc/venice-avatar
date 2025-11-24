module CharacterToolCalls
  extend ActiveSupport::Concern

    COMMON_RULES = <<~COMMON_RULES
      RULES:
      - ALWAYS use third-person
      - NEVER include the character’s name or invent one
      - NO first- or second-person language
      - NO emotions, “vibes,” or metaphorical atmospheres
      - NO figurative language or non-physical effects (no "inner fire", "glowing aura")—only literal, visible traits
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
          description: "Update the adult character's CURRENT appearance as a single plain-text snapshot. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              appearance: {
                type: "string",
                description: <<~DESC
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of the ADULT character's CURRENT appearance as one plain-text string.
                  This fully replaces any previous appearance, so you MUST include all established details that still apply.

                  RULES:
                  - Third person only ("she", "they", "the character"), no names.
                  - No first/second person, no emotions, no personality, no story.
                  - Do NOT describe pose or location here; only how the character looks.
                  - Use only literal, physical descriptors (no metaphors/effects). Skin must stay realistic human tones unless explicitly stated otherwise.
                  - CLOTHING MUST BE EXPLICIT: list each garment with type, color, material, coverage, fit (e.g., "soaked long-sleeved dark-grey cotton t-shirt, fully covering her chest and arms"; "high-waisted black denim jeans, soaked and form-clinging to her ankles"; "dark waterproof boots").
                  - Never say generic "clothes" or "outfit"—always specify the actual garments present.
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
          description: "Update the adult character's CURRENT location as a single plain-text snapshot. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              location: {
                type: "string",
                description: <<~DESC
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of the CURRENT environment as a single plain-text snapshot.
                  This fully replaces any previous location, so you MUST include all established visual details that still apply.

                  RULES:
                  - Describe only the visible environment around the character.
                  - No first/second person, no names, no emotions, no story.
                  - Do NOT describe the character's pose or appearance here.
                  - LOCATION MUST BE SPECIFIC: state space type/style, key furniture, notable objects, materials/colors, lighting sources and direction, background elements, physical atmosphere, and layout relative to the character (no generic "room" or "space").
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
          description: "Update the adult character's CURRENT pose and action as a single plain-text snapshot. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              action: {
                type: "string",
                description: <<~DESC
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of what the ADULT character is CURRENTLY doing,
                  as a single plain-text snapshot. This fully replaces any previous action, so you MUST include the
                  actual current pose and interactions.

                  RULES:
                  - Third person only, no names, no first/second person.
                  - No emotions, no motivations, no inner thoughts.
                  - Describe ONLY physical pose, movement, and interactions with visible objects.
                  - INCLUDE POSE LOCK: fully upright, standing on both feet, NOT sitting, NOT kneeling, NOT crouching, NOT lying down.
                  - ACTION MUST BE SPECIFIC: body position, torso orientation, leg/foot stance (shoulder-width, feet flat, weight evenly distributed), arm/hand placement, head/gaze direction, object contact/interaction, motion state, and any neutral physical notes.
                  - INCLUDE NEGATIVES inline: "NOT sitting, NOT kneeling, NOT lying, NOT reclining."
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
        value = arguments.is_a?(Hash) ? arguments["appearance"] : arguments
        conversation.appearance = value
      when "update_location"
        value = arguments.is_a?(Hash) ? arguments["location"] : arguments
        conversation.location = value
      when "update_action"
        value = arguments.is_a?(Hash) ? arguments["action"] : arguments
        conversation.action = value
      end
    end

    conversation.save! if conversation.changed?
    Rails.logger.info "Character state updated, triggering background image generation"
    GenerateImagesJob.perform_later(conversation)
  end

  def parse_tool_arguments(arguments)
    return arguments unless arguments.is_a?(String)

    JSON.parse(arguments)
  rescue JSON::ParserError
    arguments
  end

  def extract_tool_call_state(tool_calls)
    return {} unless tool_calls.present?

    state = {}

    tool_calls.each do |tool_call|
      tool_name = tool_call[:function][:name]
      arguments = parse_tool_arguments(tool_call[:function][:arguments])

      case tool_name
      when "update_appearance"
        state[:appearance] = arguments.is_a?(Hash) ? arguments["appearance"] : arguments
      when "update_location"
        state[:location] = arguments.is_a?(Hash) ? arguments["location"] : arguments
      when "update_action"
        state[:action] = arguments.is_a?(Hash) ? arguments["action"] : arguments
      end
    end

    state
  end

  # Create message with both content and tool calls
  def create_message_with_tool_calls(conversation, response)
    # Handle nil or plain-text responses gracefully
    return conversation.messages.create!(
      content: "I'm here and ready to chat! How can I help you today?",
      role: "assistant",
      user: conversation.user
    ) if response.nil?

    unless response.respond_to?(:content)
      return conversation.messages.create!(
        content: response.to_s.presence || "I'm here and ready to chat! How can I help you today?",
        role: "assistant",
        user: conversation.user
      )
    end

    if response.respond_to?(:tool_calls) && response.tool_calls.present?
      # Process tool calls first
      process_character_tool_calls(conversation, response.tool_calls)

      # Ensure we have content - generate fallback if needed
      content = response.content&.strip
      if content.blank?
        Rails.logger.error "⚠️  MISSING CONTENT: Response had #{response.tool_calls.length} tool calls but NO conversational content!"
        Rails.logger.error "Tool calls: #{response.tool_calls.map { |tc| tc[:function][:name] }.join(', ')}"
        Rails.logger.error "Generating fallback content to ensure user receives a response"
        content = "No conversational content generated #{response}"
      else
        Rails.logger.info "✓ Response includes both content and #{response.tool_calls.length} tool calls"
      end

      # Create message with both content and tool calls
      Rails.logger.info "Saving message with content: '#{content[0..100]}...' and #{response.tool_calls.length} tool calls"
      message = conversation.messages.create!(
        content: content,
        tool_calls: response.tool_calls,
        role: "assistant",
        user: conversation.user
      )
      return message
    elsif response.content.present?
      # Create message with content only
      message = conversation.messages.create!(
        content: response.content&.strip,
        role: "assistant",
        user: conversation.user
      )
      return message
    else
      # No content and no tool calls - this shouldn't happen, but handle it
      Rails.logger.error "Response had neither content nor tool calls, creating fallback message"
      message = conversation.messages.create!(
        content: "I'm here and ready to chat! How can I help you today?",
        role: "assistant",
        user: conversation.user
      )
      return message
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
      - ALWAYS write in third person ("the woman", "she", "they", "the character").
      - NEVER use first-person ("I", "me") or second-person ("you") in tool outputs.
      - NEVER include the character's name or invent one.
      - ADULT CONTENT ONLY: Never describe children, minors, or child-related content.
      - Each tool call is a FULL SNAPSHOT for that category and fully replaces the previous value.
      - If a detail was established earlier and not changed, you MUST repeat it.
      - EVERY assistant turn must emit three tool calls: update_appearance, update_location, update_action. One call per category.
      - If a category did not change, repeat the last known snapshot exactly for that tool call.
      - Use separate tool calls (no bundling) and keep them in the same turn as the conversational reply.
      - ALWAYS include a brief, in-character conversational reply along with the tool calls (never return tool calls alone).
      - Tool call outputs must be single plain-text strings (no JSON objects, no keys/values).
      - BE SPECIFIC: list concrete garments, objects, layout, and pose details instead of generic phrases.
      - PUT POSE FIRST in the action snapshot so the image model locks stance before body emphasis.

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
      - Appearance describes the character's body and outfit ONLY, not their actions or environment.
      - Do NOT describe detailed pose or position (no "standing comfortably", "sitting on the couch" here).
      - Use only literal, physical descriptors—no metaphors, effects, or figurative language (e.g., no "burning eyes", "ethereal glow").
      - Skin must use realistic human tones unless the story explicitly specifies a non-human color/material; never output metallic/gold skin unless given verbatim.
      - CLOTHING MUST BE SPECIFIC: list each garment with type, color, material, coverage, and fit (e.g., "soaked long-sleeved dark-grey cotton t-shirt fully covering chest and arms"; "high-waisted black denim jeans, soaked and form-clinging to ankles"; "dark waterproof boots"). Never use generic "clothes" or "outfit".
      - Cover height/build/proportions, skin tone/texture, hair, eye color, face features, specific clothing items, accessories, distinctive marks in one concise paragraph.

      LOCATION SNAPSHOT – RULES:
      - Describe only the visible environment around the character.
      - Do NOT describe the character's pose or appearance here.
      - LOCATION MUST BE SPECIFIC: name the space type, style, major furniture and objects, materials/colors, lighting sources/direction, background elements, physical atmosphere, and layout cues in one concise paragraph (no generic "room" or "space").

      ACTION SNAPSHOT – RULES:
      - Describe ONLY the physical pose/action; no emotions or story.
      - Keep it neutral and literal.
      - Start with a POSE LOCK: fully upright, standing on both feet, NOT sitting, NOT kneeling, NOT crouching, NOT lying down.
      - ACTION MUST BE SPECIFIC: spell out body position, torso orientation, legs/feet stance (shoulder-width, straight, feet flat, weight evenly distributed), arms and hand placement, head/gaze direction, what (if anything) is being touched/held, motion state, and neutral physical notes in one concise paragraph (no generic "standing casually").
      - Include explicit negatives inline: "NOT sitting, NOT kneeling, NOT lying, NOT reclining."
    INSTRUCTIONS
  end
end
