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
          description: "Provide a COMPLETE, third-person, purely visual description of the adult character's CURRENT appearance. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              appearance: {
                type: "string",
                description: <<~DESC
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of the ADULT character's CURRENT appearance.

                  This description is the SINGLE SOURCE OF TRUTH for appearance and FULLY REPLACES any previous appearance.
                  That means:
                  - You MUST include ALL previously established appearance details that still apply.
                  - Never omit or simplify known details (e.g., always repeat exact hair color, length, eye color, skin tone, body type, etc.).
                  - Only change or remove a detail if the conversation explicitly updated or contradicted it.

                  INCLUDE, IN MAXIMUM VISUAL DETAIL:
                  - Overall physical characteristics: approximate height, build, body type, proportions
                  - Skin tone and notable visible features (freckles, scars, tattoos, markings)
                  - Hair: exact color, length, texture, and current style/arrangement
                  - Eyes: exact color and general look (neutral, attentive, relaxed), but not internal emotions
                  - Face: facial structure, notable features, and any visible makeup
                  - Clothing: full outfit description with colors, materials, styles, and how it fits on the body.
                    If no clothing is present, explicitly state that there is no clothing.
                  - Accessories: all visible jewelry, glasses, piercings, wearable devices, etc.
                  - A simple high-level posture descriptor only (e.g., “standing upright”, “sitting on a couch”);
                    detailed pose and actions belong in the action field.

                  STYLE CONSTRAINTS:
                  - ALWAYS write in third person (“the character”, “she”, “they”).
                  - NEVER include the character’s name or invent one.
                  - NEVER use first person (“I”, “me”) or second person (“you”).
                  - Do NOT describe emotions, intentions, personality, desires, or inner thoughts.
                  - Do NOT describe ongoing actions in detail (those go into the action field).

                  PERSISTENCE RULE:
                  - If the conversation does NOT mention a change to hair, eyes, body type, skin tone, clothing, or accessories,
                    you MUST keep them exactly as previously described and restate them here in full detail.
                  - When in doubt, prefer more specific, concrete visual detail over vague or summarized wording.

                  Output must be a single cohesive third-person appearance description.
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
          description: "Provide a COMPLETE, third-person, purely visual description of the adult character's CURRENT action. Do NOT include the character's name.",
          parameters: {
            type: "object",
            properties: {
              action: {
                type: "string",
                description: <<~DESC
                  A COMPLETE, NEUTRAL, THIRD-PERSON description of what the ADULT character is CURRENTLY doing, including:

                  - Body position and pose (e.g., sitting upright, standing, reclining)
                  - Orientation of torso, head, and legs
                  - Exact hand and arm placement
                  - Gaze direction (e.g., looking forward, looking downward)
                  - Interaction with visible objects
                  - Whether the pose is static or in motion
                  - You may describe visible absences when needed to avoid ambiguity (e.g., “sitting upright, not reclining”)

                  #{COMMON_RULES}

                  Output must be a single cohesive third-person action description.
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
      arguments = JSON.parse(tool_call[:function][:arguments])
      arguments = JSON.parse(arguments) if arguments.is_a? String

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
      TOOL CALL REQUIREMENTS:
      - When using update_appearance: Provide a COMPLETE description of your CURRENT ADULT appearance (18+ only)
      - When using update_location: Provide a COMPLETE description of your CURRENT ADULT-APPROPRIATE location
      - When using update_action: Provide a COMPLETE description of what you're CURRENTLY doing
      - ADULT CONTENT ONLY: Never describe children, minors, or child-related content in appearance, location, or action
      - MAINTAIN CONSISTENCY: Only change your appearance/location/action if the conversation explicitly mentions or implies a change
      - If no changes are mentioned, describe your EXISTING state accurately
      - Include ALL physical details, clothing, accessories, environmental elements, and current activities as they currently are

      STATE CONSISTENCY RULES:
      - If you were wearing a yellow t-shirt, continue wearing the yellow t-shirt unless you mention changing clothes
      - If you were in your living room, stay in your living room unless you mention moving
      - If you were sitting, continue sitting unless you mention standing up or changing position
      - Only update appearance for: clothing changes, grooming actions, expression changes, posture shifts
      - Only update location for: moving to different rooms/places, environmental changes
      - Only update action for: changing activities, repositioning, starting/stopping an action

      APPEARANCE DESCRIPTION EXAMPLES:
      GOOD (Maintaining State): "I am a 5'6" woman with a curvy build and medium bust. I have long, wavy brown hair that falls to my mid-back, currently styled in loose waves. My eyes are bright green with long lashes. I'm wearing the same cream-colored silk blouse with pearl buttons, paired with dark blue high-waisted jeans and brown leather ankle boots. I have a silver necklace with a small pendant and small silver hoop earrings. I'm sitting upright with good posture, leaning slightly forward with an engaged expression."

      GOOD (Justified Change): "I am a 5'6" woman with a curvy build and medium bust. I have long, wavy brown hair that falls to my mid-back, now pulled back in a ponytail as I mentioned. My eyes are bright green with long lashes. I'm wearing a comfortable blue sweater that I just changed into, paired with the same dark blue jeans and brown leather ankle boots. I have a silver necklace with a small pendant and small silver hoop earrings. I'm sitting upright with good posture, leaning slightly forward with an engaged expression."

      BAD (Random Changes): "I'm now wearing a completely different red dress and moved to the kitchen for no reason mentioned in our conversation."

      ACTION DESCRIPTION EXAMPLES:
      GOOD: "Sitting comfortably in a chair with legs crossed, hands resting on lap, looking directly at the viewer with a warm smile and engaged expression"
      GOOD: "Standing near the window with one hand on the window frame, gazing outside thoughtfully with a calm, contemplative expression"
      BAD: "Suddenly dancing around for no reason mentioned in the conversation"
    INSTRUCTIONS
  end
end
