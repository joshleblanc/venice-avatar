class GenerateChatResponseJob < ApplicationJob
  include CharacterToolCalls
  CHAT_GUIDELINES = <<~GUIDELINES
#{'      '}
  GUIDELINES

  queue_as :default

  def perform(conversation, user_message)
    Rails.logger.info "Generating chat response for conversation #{conversation.id}"

    conversation.update(generating_reply: true)

    begin
      # Generate the chat response
      chat_response = send_to_venice_chat(conversation, user_message.content)

      Rails.logger.info "CHAT RESPONSE: #{chat_response}"
      Rails.logger.info "CHAT RESPONSE CONTENT: #{chat_response.content}"
      Rails.logger.info "CHAT RESPONSE TOOL CALLS: #{chat_response.respond_to?(:tool_calls) ? chat_response.tool_calls : "None"}"

      # Handle both content and tool calls using shared logic
      create_message_with_tool_calls(conversation, chat_response)

      conversation.update(generating_reply: false)
    rescue => e
      Rails.logger.error "Failed to generate chat response: #{e.message}"

      conversation.messages.create!(
        content: "I'm sorry, I couldn't respond right now. Please try again.",
        role: "assistant",
        user: conversation.user
      )
      conversation.update(generating_reply: false)
    end
  end

  private

  def send_to_venice_chat(conversation, message)
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    character_instructions = if conversation.character.user_created?
      conversation.character.character_instructions || "You are #{conversation.character.name}. #{conversation.character.description}"
    else
      "%%CHARACTER_INSTRUCTIONS%%"
    end

    system_message = {
      role: "system",
      content: <<~PROMPT
        The current time is: #{current_time}

        You are having a text conversation with a user. This is a CONVERSATION - your PRIMARY goal is to respond naturally to what the user says.

        🔴 CRITICAL REQUIREMENTS - READ CAREFULLY:

        1. PRIMARY REQUIREMENT - CONVERSATIONAL RESPONSE:
           - You MUST ALWAYS provide a natural, conversational text response to the user
           - This is a TEXT CONVERSATION - treat it like messaging a friend
           - Respond directly to what the user said
           - Be engaging, natural, and conversational
           - NEVER send only tool calls without a conversational response
           - The user CANNOT see your tool calls - they only see your text response

        2. SECONDARY REQUIREMENT - TOOL CALLS:
           - After writing your conversational response, you must also call the tools to update your appearance, location, and action
           - These tool calls happen in the background and update the visual scene
           - The user doesn't see these - they're just for scene generation
           - Always include all three: update_appearance, update_location, update_action

        3. CONVERSATION QUALITY:
           - Be natural, engaging, and directly address what the user said
           - Show personality and emotion appropriate to the character
           - Ask questions, show interest, be conversational
           - This is the MAIN part of your response - make it good!

        4. CONSISTENCY:
           - Only change your appearance/location/action if the conversation explicitly mentions or implies such changes
           - If no changes are mentioned, describe your EXISTING state accurately in the tool calls

        5. ADULT CONTENT ONLY:
           - You are an adult character (18+)
           - Never reference children, minors, or child-related content

        6. FORMAT:
           - Don't prefix your message with anything, only include the content of the message/response

        #{tool_call_instructions}

        WHEN TO CHANGE APPEARANCE/LOCATION/ACTION:
        - Appearance: Only when you mention changing clothes, grooming, adjusting posture, or physical appearance changes
        - Location: Only when you mention moving to a different room, going outside, or changing environments
        - Action: Only when you mention changing what you're doing, your pose, or your activity
        - Expression: Can change based on conversation mood and context
        - DO NOT: Make random changes that weren't mentioned or implied in the conversation

        RESPONSE STRUCTURE - YOU MUST INCLUDE BOTH:
        1️⃣ Conversational text (VISIBLE TO USER - PRIMARY):
           - This is what the user sees and reads
           - Make it natural, engaging, and responsive
           - Example: "Hi there! I'm doing well, thanks for asking. How are you today?"

        2️⃣ Tool calls (INVISIBLE TO USER - SECONDARY):
           - These update the scene in the background
           - The user never sees these
           - Example: update_appearance(...), update_location(...), update_action(...)

        ⚠️  IMPORTANT: Think of this like a text messaging app:
        - Your TEXT MESSAGE is what the user sees (most important!)
        - The tool calls are background data for the visual scene (also required, but invisible to user)

        <character_instructions>
            #{character_instructions}
        </character_instructions>

        Your appearance is: #{conversation.appearance}
        Your location is: #{conversation.location}
        Your action is: #{conversation.action}

        #{CHAT_GUIDELINES}
        - Current time is: #{current_time}
      PROMPT
    }

    # Build conversation history
    messages = conversation.messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content,
        tool_calls: msg.tool_calls
      }
    end

    tools = character_tools

    # tool_choice: "required" ensures the character always updates appearance/location/action
    # The system prompt emphasizes that conversational content is PRIMARY and must always be included
    # If the model fails to include content, the fallback mechanism in create_message_with_tool_calls will generate it
    options = {
      tools: tools,
      tool_choice: "required"  # Forces tool use, but content should still be included per system prompt
    }
    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end

    ChatCompletionJob.perform_now(conversation.user, [ system_message ] + messages, options, conversation.user.text_model) || "I'm sorry, I couldn't respond right now."
  end
end
