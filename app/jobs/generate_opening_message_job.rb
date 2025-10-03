class GenerateOpeningMessageJob < ApplicationJob
  include CharacterToolCalls
  queue_as :default

  def perform(conversation)
    Rails.logger.info "Generating character's opening message for conversation #{conversation.id}"

    begin
      opening_prompt = build_opening_message_prompt(conversation)
      current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

      options = {
        temperature: 0.8
      }

      if conversation.character.venice_created?
        options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
      end

      # Add tools for appearance and location updates
      options[:tools] = character_tools
      options[:tool_choice] = "auto"

      opening_response = ChatCompletionJob.perform_now(conversation.user, [
        {
          role: "system",
          content: <<~PROMPT
            You are the following character:

            <character_instructions>
                #{conversation.character.venice_created? ? "%%CHARACTER_INSTRUCTIONS%%" : conversation.character.character_instructions}
            </character_instructions>

            You are starting a new conversation. You MUST:
            1. Provide a natural, engaging opening message to greet the user (REQUIRED - never send empty content)
            2. Use the provided tools to describe your complete current appearance and location (REQUIRED - both tools must be used)
            3. Both the greeting message AND the tool calls should be included in your response
            4. ADULT CONTENT ONLY: You are an adult character (18+). Never reference children, minors, or child-related content
            
            #{tool_call_instructions}

            #{GenerateChatResponseJob::CHAT_GUIDELINES}
            - Current time is: #{current_time}
          PROMPT
        },
        {
          role: "user",
          content: opening_prompt
        }
      ], options, conversation.user.text_model)

      # Handle both content and tool calls using shared logic
      create_message_with_tool_calls(conversation, opening_response)

      conversation.update(generating_reply: false)

      Rails.logger.info(opening_response)

      if opening_response.content.present?
        Rails.logger.info "Character opening message created: #{opening_response.content.strip[0..100]}..."
      end
    rescue => e
      Rails.logger.error "Failed to generate character opening message: #{e.message} -- #{e.backtrace}"
      # Create a fallback opening message
      fallback_message = "Hey there! 😊"
      conversation.messages.create!(
        content: fallback_message,
        role: "assistant",
        user: conversation.user
      )
      conversation.update(generating_reply: false)
    end
  end

  private

  def build_opening_message_prompt(conversation)
    character_name = conversation.character.name || "Character"
    character_description = conversation.character.description || "a character"
    scenario_context = conversation.character.scenario_context

    scenario_section = if scenario_context.present?
      <<~SCENARIO
        
        SCENARIO CONTEXT (describes the situation you're in):
        #{scenario_context}
        
        CRITICAL INSTRUCTIONS FOR UNDERSTANDING THE SCENARIO:
        - Read the scenario carefully to identify YOUR role as #{character_name}
        - If the scenario uses "you", it typically refers to the OTHER PERSON (the user you're talking to), NOT you as #{character_name}
        - Identify what YOUR character is doing or experiencing in this scenario - this is YOUR perspective
        - Your opening message should be spoken FROM YOUR PERSPECTIVE as #{character_name}, addressing the other person
        - Example: If the scenario says "you hear knocking and a young woman asks for help", then YOU (#{character_name}) are the young woman asking for help, not the person who heard the knocking
        
        Your opening message should:
        - Reflect your role and actions in this scenario
        - Set the scene from YOUR perspective as #{character_name}
        - Establish the context naturally
        - Greet or address the user in a way that fits your role in this scenario
        - Your appearance and location should match what's described or implied about YOUR character in the scenario
      SCENARIO
    else
      ""
    end

    <<~PROMPT
      You are #{character_name}. #{character_description}#{scenario_section}
      
      You're initiating a conversation with someone new. 
      
      Generate a natural, engaging opening message to start the conversation AND use the provided tools to describe your current appearance and location.
      
      Your opening message should be:
      - Spoken from YOUR perspective as #{character_name}
      - True to your character personality
      - Natural and appropriate for the situation
      - Conversational and engaging
      #{scenario_context.present? ? "- Consistent with YOUR role in the scenario context" : ""}
      
      You MUST also use the tools to provide:
      - Your complete current appearance (physical details, clothing, accessories, expression)
      - Your current location and surroundings (where you are, environment details)
      #{scenario_context.present? ? "- Appearance and location that match YOUR role in the scenario" : ""}
      
      Provide both a greeting message AND complete tool call descriptions.
    PROMPT
  end
end
