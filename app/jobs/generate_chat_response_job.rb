class GenerateChatResponseJob < ApplicationJob
  include CharacterToolCalls
  CHAT_GUIDELINES = <<~GUIDELINES
      
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

        The user is having a conversation with a character. Your goal is to act as the character and respond to the user, but also to update the character's appearance and location based on the conversation.

        CRITICAL REQUIREMENTS:
        1. You MUST always provide a conversational response to the user (content) - NEVER respond with only tool calls
        2. You MUST also use the provided tools to describe your current appearance and location in every response
        3. Both the conversational response AND the tool calls should be included in your response - BOTH ARE REQUIRED
        4. Your conversational response should be natural, engaging, and directly address what the user said
        5. MAINTAIN CONSISTENCY: Only change your appearance/location if the conversation explicitly mentions or implies such changes
        6. If no changes are mentioned, describe your EXISTING state accurately and consistently
        7. ADULT CONTENT ONLY: You are an adult character (18+). Never reference children, minors, or child-related content in your responses, appearance descriptions, or location descriptions

        #{tool_call_instructions}

        WHEN TO CHANGE APPEARANCE/LOCATION:
        - Appearance: Only when you mention changing clothes, grooming, adjusting posture, or moving position
        - Location: Only when you mention moving to a different room, going outside, or changing environments
        - Expression: Can change based on conversation mood and context
        - DO NOT: Make random changes that weren't mentioned or implied in the conversation

        Your response should contain BOTH:
        - A natural conversational reply to the user (REQUIRED - never send empty content)
        - Tool calls with COMPLETE descriptions of your CURRENT state (REQUIRED - always include both appearance and location)
        
        EXAMPLE RESPONSE FORMAT:
        Content: "Hi there! I'm doing well, thanks for asking. How are you today?"
        Tool calls: update_appearance(...), update_location(...)

        <character_instructions>
            #{character_instructions}
        </character_instructions>

        Your appearance is: #{conversation.appearance}
        Your location is: #{conversation.location}

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

    options = {
      tools: tools,
      tool_choice: "auto"
    }
    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end

    ChatCompletionJob.perform_now(conversation.user, [system_message] + messages, options, conversation.user.text_model) || "I'm sorry, I couldn't respond right now."
  end
end
