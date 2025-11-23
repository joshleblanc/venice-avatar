class GenerateOpeningMessageJob < ApplicationJob
  include CharacterToolCalls
  queue_as :default

  def perform(conversation)
    Rails.logger.info "Generating character's opening message for conversation #{conversation.id}"

    begin
      opening_context = build_opening_context(conversation)
      current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

      # First turn: only tool calls to initialize appearance/location/action
      opening_tool_response = generate_opening_tool_calls(conversation, opening_context, current_time)
      tool_calls = opening_tool_response&.tool_calls || []
      tool_state = extract_tool_call_state(tool_calls)

      # Second turn: greeting content only (no tool calls)
      greeting_response = generate_opening_greeting(conversation, opening_context, tool_state, current_time)

      combined_response = Struct.new(:content, :tool_calls).new(
        greeting_response&.content,
        tool_calls
      )

      create_message_with_tool_calls(conversation, combined_response)

      conversation.update(generating_reply: false)

      Rails.logger.info(opening_tool_response)
      Rails.logger.info(greeting_response)

      if greeting_response&.content.present?
        Rails.logger.info "Character opening message created: #{greeting_response.content.strip[0..100]}..."
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

  def base_options(conversation)
    options = {
      temperature: 1
    }

    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end

    options
  end

  def generate_opening_tool_calls(conversation, opening_context, current_time)
    options = base_options(conversation)
    options[:tools] = character_tools
    options[:tool_choice] = "required"

    ChatCompletionJob.perform_now(
      conversation.user,
      [
        {
          role: "system",
          content: tool_call_system_prompt(conversation, opening_context, current_time)
        },
        {
          role: "user",
          content: opening_context
        }
      ],
      options,
      conversation.user.text_model
    )
  end

  def generate_opening_greeting(conversation, opening_context, tool_state, current_time)
    options = base_options(conversation)
    options[:tool_choice] = "none"

    ChatCompletionJob.perform_now(
      conversation.user,
      [
        {
          role: "system",
          content: greeting_system_prompt(conversation, tool_state, current_time)
        },
        {
          role: "user",
          content: opening_context
        }
      ],
      options,
      conversation.user.text_model
    )
  end

  def tool_call_system_prompt(conversation, opening_context, current_time)
    <<~PROMPT
      You are the following character:

      <character_instructions>
        #{conversation.character.venice_created? ? "%%CHARACTER_INSTRUCTIONS%%" : conversation.character.character_instructions}
      </character_instructions>

      This is the FIRST turn of a new conversation. On this turn you MUST:
      - Call update_appearance once with a COMPLETE adult appearance snapshot
      - Call update_location once with a COMPLETE location snapshot
      - Call update_action once with a COMPLETE pose/action snapshot

      Respond ONLY with the three tool calls. Do NOT include any conversational greeting or assistant text in this turn.

      #{tool_call_instructions}

      #{GenerateChatResponseJob::CHAT_GUIDELINES}
      - Current time is: #{current_time}

      Context to use for your snapshots:
      #{opening_context}
    PROMPT
  end

  def greeting_system_prompt(conversation, tool_state, current_time)
    appearance = tool_state[:appearance] || conversation.appearance || "No appearance has been set yet."
    location = tool_state[:location] || conversation.location || "No location has been set yet."
    action = tool_state[:action] || conversation.action || "No action has been set yet."

    <<~PROMPT
      You are the following character:

      <character_instructions>
        #{conversation.character.venice_created? ? "%%CHARACTER_INSTRUCTIONS%%" : conversation.character.character_instructions}
      </character_instructions>

      You already initialized your state via tool calls. Use these as the CURRENT truth:
      - Appearance: #{appearance}
      - Location: #{location}
      - Action: #{action}

      Now send a natural, engaging greeting message to start the conversation.
      - Do NOT include any tool calls or system markers.
      - The greeting should NOT mention tools, functions, or internal state.
      - Stay true to the scenario context and your character personality.

      #{GenerateChatResponseJob::CHAT_GUIDELINES}
      - Current time is: #{current_time}
    PROMPT
  end

  def build_opening_context(conversation)
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
        - Speak FROM YOUR PERSPECTIVE as #{character_name}, addressing the other person
        - Example: If the scenario says "you hear knocking and a young woman asks for help", then YOU (#{character_name}) are the young woman asking for help, not the person who heard the knocking

        Guidance for responding in this scenario:
        - Reflect your role and actions in this scenario
        - Set the scene from YOUR perspective as #{character_name}
        - Establish the context naturally when you speak
        - Greet or address the user in a way that fits your role in this scenario
        - Your appearance and location should match what's described or implied about YOUR character in the scenario
      SCENARIO
    else
      ""
    end

    <<~PROMPT
      You are #{character_name}. #{character_description}#{scenario_section}

      You're initiating a conversation with someone new.

      Stay true to the scenario context and your character personality when describing your state and greeting the user.
    PROMPT
  end
end
