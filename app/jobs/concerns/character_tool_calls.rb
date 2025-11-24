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
          name: "reply",
          description: "Send your in-character conversational reply to the user. This is REQUIRED on every turn.",
          parameters: {
            type: "object",
            properties: {
              message: {
                type: "string",
                description: "Your in-character conversational reply to the user. Stay in character, be natural and engaging. This is the text the user will see."
              }
            },
            required: ["message"]
          }
        }
      },
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
  # Returns the reply content if a reply tool call was found
  def process_character_tool_calls(conversation, tool_calls)
    return nil unless tool_calls.present?

    reply_content = nil
    state_changed = false

    tool_calls.each do |tool_call|
      tool_name = tool_call[:function][:name]
      arguments = parse_tool_arguments(tool_call[:function][:arguments])

      Rails.logger.debug "Processing tool call: #{tool_name} with arguments: #{arguments.inspect}"

      case tool_name
      when "reply"
        reply_content = arguments.is_a?(Hash) ? arguments["message"] : arguments
        Rails.logger.info "Extracted reply from tool call: #{reply_content&.first(100)}..."
      when "update_appearance"
        value = arguments.is_a?(Hash) ? arguments["appearance"] : arguments
        if value.present? && value != conversation.appearance
          conversation.appearance = value
          state_changed = true
        end
      when "update_location"
        value = arguments.is_a?(Hash) ? arguments["location"] : arguments
        if value.present? && value != conversation.location
          conversation.location = value
          state_changed = true
        end
      when "update_action"
        value = arguments.is_a?(Hash) ? arguments["action"] : arguments
        if value.present? && value != conversation.action
          conversation.action = value
          state_changed = true
        end
      end
    end

    if conversation.changed?
      conversation.save!
      Rails.logger.info "Character state updated (changed: #{state_changed})"
    end

    # Only trigger image generation if state actually changed
    if state_changed
      Rails.logger.info "State changed, triggering background image generation"
      GenerateImagesJob.perform_later(conversation)
    end

    reply_content
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
      when "reply"
        state[:reply] = arguments.is_a?(Hash) ? arguments["message"] : arguments
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
    if response.nil?
      Rails.logger.error "Response was nil, using fallback"
      return conversation.messages.create!(
        content: generate_fallback_content(conversation, []),
        role: "assistant",
        user: conversation.user
      )
    end

    unless response.respond_to?(:content)
      return conversation.messages.create!(
        content: response.to_s.presence || generate_fallback_content(conversation, []),
        role: "assistant",
        user: conversation.user
      )
    end

    if response.respond_to?(:tool_calls) && response.tool_calls.present?
      # Process tool calls and extract reply content
      reply_from_tool = process_character_tool_calls(conversation, response.tool_calls)

      # Priority: 1) reply tool content, 2) response.content, 3) fallback
      content = reply_from_tool.presence || response.content&.strip

      if content.blank?
        Rails.logger.error "⚠️  MISSING CONTENT: Response had #{response.tool_calls.length} tool calls but NO reply!"
        Rails.logger.error "Tool calls: #{response.tool_calls.map { |tc| tc[:function][:name] }.join(', ')}"
        content = generate_fallback_content(conversation, response.tool_calls)
      else
        Rails.logger.info "✓ Response includes content and #{response.tool_calls.length} tool calls"
      end

      message = conversation.messages.create!(
        content: content,
        tool_calls: response.tool_calls,
        role: "assistant",
        user: conversation.user
      )
      return message
    elsif response.content.present?
      # Content only (no tool calls) - still valid
      message = conversation.messages.create!(
        content: response.content&.strip,
        role: "assistant",
        user: conversation.user
      )
      return message
    else
      # No content and no tool calls
      Rails.logger.error "Response had neither content nor tool calls"
      message = conversation.messages.create!(
        content: generate_fallback_content(conversation, []),
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
      TOOL CALL REQUIREMENTS:

      You MUST call the `reply` tool on EVERY turn with your conversational response.

      You also maintain three pieces of visual state via optional tools:
      - update_appearance: what the adult character (18+) looks like
      - update_location: where the character is
      - update_action: what the character is physically doing / how they are posed

      REQUIRED EVERY TURN:
      - Call `reply` with your in-character message to the user. This is MANDATORY.

      STATE UPDATE TOOLS - WHEN TO CALL:
      These tools update the visual scene. Call them whenever the scene should change.

      `update_location` - Call when:
      - User suggests going somewhere AND you agree ("Let's go to the kitchen" → call update_location with kitchen description)
      - Character decides to move ("I'll head to the bedroom" → call update_location)
      - Scene transitions ("We arrive at the park" → call update_location)
      - ANY movement to a new place, even within the same building

      `update_appearance` - Call when:
      - Clothing changes (putting on, taking off, getting wet, etc.)
      - Hair/makeup changes
      - Accessories added/removed
      - Any visible physical change

      `update_action` - Call when:
      - Pose changes (standing → sitting, arms crossed → hands on hips)
      - Starting/stopping an activity
      - Interacting with objects differently

      IMPORTANT: If your reply implies a scene change, you MUST call the corresponding tool.
      Example: If you say "Sure, let's go to the kitchen!" you MUST also call update_location.
      
      If nothing changed in a category, do NOT call that tool; the previous state remains.

      TOOL OUTPUT RULES:
      - ALWAYS write state updates in third person ("the woman", "she", "they").
      - NEVER use first-person ("I", "me") in state tool outputs (but DO use first-person in the reply tool).
      - NEVER include the character's name in state outputs.
      - ADULT CONTENT ONLY: Never describe children, minors, or child-related content.
      - Each state tool call is a FULL SNAPSHOT that replaces the previous value.
      - If a detail was established earlier and not changed, you MUST repeat it in the snapshot.
      - Tool call outputs must be single plain-text strings (no JSON objects).
      - BE SPECIFIC: list concrete garments, objects, layout, and pose details.

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
