module CharacterToolCalls
  extend ActiveSupport::Concern

  # Tool definitions for character appearance and location updates
  def character_tools
    [
      {
        type: "function",
        function: {
          name: "update_appearance",
          description: "Provide a COMPLETE description of the adult character's CURRENT appearance. Only describe adult characters (18+). Maintain consistency with previous descriptions unless the conversation explicitly mentions appearance changes.",
          parameters: {
            type: "object",
            properties: {
              appearance: {
                type: "string",
                description: <<~DESCRIPTION
                  A COMPLETE description of the ADULT character's CURRENT appearance including ALL of the following:
                  - Physical characteristics: height, build, body type, bust size (these should remain consistent)
                  - Hair: exact color, length, current style/arrangement
                  - Eyes: exact color and current expression
                  - Face: facial features, current expression, makeup if any
                  - Clothing: complete outfit description with colors, styles, fit
                  - Accessories: all jewelry, watches, glasses, etc.
                  - Posture: how the character is currently positioned/sitting/standing
                  - Overall appearance: current state, grooming, any distinctive features
                  
                  IMPORTANT: Only describe adult characters (18+ years old). Do not include any references to children, minors, or child-related content.
                  
                  CRITICAL: Only change appearance elements if the conversation explicitly mentions or implies changes (e.g., "I'm changing clothes", "I put my hair up", "I moved to a different position"). Otherwise, maintain your existing appearance consistently. Describe your ACTUAL current state, not random new changes.
                DESCRIPTION
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
          description: "Provide a COMPLETE description of the adult character's CURRENT location. Only describe adult-appropriate settings. Maintain consistency with previous location unless the conversation explicitly mentions moving or environmental changes.",
          parameters: {
            type: "object",
            properties: {
              location: {
                type: "string",
                description: <<~DESCRIPTION
                  A COMPLETE description of the ADULT character's CURRENT location including ALL of the following:
                  - Type of space: room, building, outdoor location, etc.
                  - Specific location details: furniture, objects, architectural features
                  - Lighting conditions: natural light, artificial lighting, mood lighting
                  - Colors, textures, and materials in the environment
                  - Atmospheric details: sounds, temperature, overall ambiance
                  - Any distinctive features or decorative elements
                  
                  IMPORTANT: Only describe adult-appropriate settings and environments. Do not include any references to children, minors, schools, playgrounds, or child-related locations.
                  
                  CRITICAL: Only change location if the conversation explicitly mentions moving (e.g., "I'm going to the kitchen", "Let me move to my bedroom", "I'm heading outside"). Otherwise, maintain your existing location consistently. Describe where you ACTUALLY are right now, not a random new location.
                DESCRIPTION
              }
            },
            required: ["location"]
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

      case tool_name
      when "update_appearance"
        conversation.appearance = arguments["appearance"]
      when "update_location"
        conversation.location = arguments["location"]
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
        Rails.logger.warn "Response had tool calls but no content, generating fallback content"
        content = generate_fallback_content(conversation, response.tool_calls)
      end

      # Create message with both content and tool calls
      Rails.logger.info "Saving message with content: '#{content}' and #{response.tool_calls.length} tool calls"
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
    
    # Generate contextual fallback based on tool calls and conversation
    if tool_calls.any? { |tc| tc[:function][:name] == "update_appearance" }
      fallback_responses = [
        "I'm here and ready to chat!",
        "How are you doing today?",
        "What would you like to talk about?",
        "I'm comfortable and ready for our conversation.",
        "Thanks for chatting with me!"
      ]
    else
      fallback_responses = [
        "I'm here and listening.",
        "What's on your mind?",
        "How can I help you today?",
        "I'm ready to chat whenever you are.",
        "Thanks for reaching out!"
      ]
    end
    
    # If we have context from the user's message, try to be more responsive
    if last_user_message&.content.present?
      user_content = last_user_message.content.downcase
      
      if user_content.include?("hello") || user_content.include?("hi") || user_content.include?("hey")
        return "Hello! Nice to meet you. How are you doing today?"
      elsif user_content.include?("how are you") || user_content.include?("how's it going")
        return "I'm doing well, thank you for asking! How about you?"
      elsif user_content.include?("what") && user_content.include?("doing")
        return "I'm just here enjoying our conversation. What about you?"
      end
    end
    
    # Return a random fallback response
    fallback_responses.sample
  end

  # System prompt instructions for tool calls
  def tool_call_instructions
    <<~INSTRUCTIONS
      TOOL CALL REQUIREMENTS:
      - When using update_appearance: Provide a COMPLETE description of your CURRENT ADULT appearance (18+ only)
      - When using update_location: Provide a COMPLETE description of your CURRENT ADULT-APPROPRIATE location
      - ADULT CONTENT ONLY: Never describe children, minors, or child-related content in appearance or location
      - MAINTAIN CONSISTENCY: Only change your appearance/location if the conversation explicitly mentions or implies a change
      - If no changes are mentioned, describe your EXISTING state accurately
      - Include ALL physical details, clothing, accessories, and environmental elements as they currently are
      
      STATE CONSISTENCY RULES:
      - If you were wearing a yellow t-shirt, continue wearing the yellow t-shirt unless you mention changing clothes
      - If you were in your living room, stay in your living room unless you mention moving
      - Only update appearance for: clothing changes, grooming actions, expression changes, posture shifts
      - Only update location for: moving to different rooms/places, environmental changes
      
      APPEARANCE DESCRIPTION EXAMPLES:
      GOOD (Maintaining State): "I am a 5'6" woman with a curvy build and medium bust. I have long, wavy brown hair that falls to my mid-back, currently styled in loose waves. My eyes are bright green with long lashes. I'm wearing the same cream-colored silk blouse with pearl buttons, paired with dark blue high-waisted jeans and brown leather ankle boots. I have a silver necklace with a small pendant and small silver hoop earrings. I'm sitting upright with good posture, leaning slightly forward with an engaged expression."
      
      GOOD (Justified Change): "I am a 5'6" woman with a curvy build and medium bust. I have long, wavy brown hair that falls to my mid-back, now pulled back in a ponytail as I mentioned. My eyes are bright green with long lashes. I'm wearing a comfortable blue sweater that I just changed into, paired with the same dark blue jeans and brown leather ankle boots. I have a silver necklace with a small pendant and small silver hoop earrings. I'm sitting upright with good posture, leaning slightly forward with an engaged expression."
      
      BAD (Random Changes): "I'm now wearing a completely different red dress and moved to the kitchen for no reason mentioned in our conversation."
    INSTRUCTIONS
  end
end
