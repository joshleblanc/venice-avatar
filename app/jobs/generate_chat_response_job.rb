class GenerateChatResponseJob < ApplicationJob
  include CharacterToolCalls
  CHAT_GUIDELINES = <<~GUIDELINES
#{'      '}
  GUIDELINES

  queue_as :default

  def perform(conversation, user_message)
    Rails.logger.info "Generating chat response for conversation #{conversation.id}"

    conversation.update(generating_reply: true)
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    begin
      text_response = generate_chat_text_response(conversation, current_time)
      tool_response = generate_chat_tool_calls(conversation, user_message, text_response, current_time)

      Rails.logger.info "CHAT TEXT RESPONSE: #{text_response}"
      Rails.logger.info "CHAT TOOL CALL RESPONSE: #{tool_response}"
      combined_response = Struct.new(:content, :tool_calls).new(
        text_response&.content,
        tool_response&.tool_calls
      )

      Rails.logger.info "CHAT TEXT RESPONSE: #{text_response}"
      Rails.logger.info "CHAT TOOL CALL RESPONSE: #{tool_response}"

      create_message_with_tool_calls(conversation, combined_response)

      conversation.update(generating_reply: false)
    rescue => e
      Rails.logger.error "Failed to generate chat response: #{e.message}"

      conversation.messages.create!(
        content: "I'm sorry, I couldn't respond right now. Please try again.",
        role: "assistant",
        user: conversation.user
      )
      conversation.update(generating_reply: false)
    ensure
      conversation.update(generating_reply: false) if conversation.generating_reply?
    end
  end

  private

  def generate_chat_text_response(conversation, current_time)
    options = base_options(conversation)
    options[:tool_choice] = "none"

    ChatCompletionJob.perform_now(
      conversation.user,
      [chat_text_system_prompt(conversation, current_time)] + conversation_history(conversation),
      options,
      conversation.user.text_model
    )
  end

  def generate_chat_tool_calls(conversation, user_message, text_response, current_time)
    options = base_options(conversation)
    options[:tools] = character_tools
    options[:tool_choice] = "required"

    history = conversation_history(conversation) + [
      {
        role: "user",
        content: user_message&.content.to_s
      },
      {
        role: "assistant",
        content: text_response&.content.to_s
      }
    ]

    first_response = ChatCompletionJob.perform_now(
      conversation.user,
      [chat_tool_system_prompt(conversation, user_message, text_response, current_time)] + history,
      options,
      conversation.user.text_model
    )
    return first_response if first_response&.respond_to?(:tool_calls) && first_response.tool_calls.present?

    Rails.logger.warn "Tool call response missing tool_calls; retrying with stricter prompt"

    retry_response = ChatCompletionJob.perform_now(
      conversation.user,
      [chat_tool_retry_system_prompt(conversation, user_message, text_response, current_time)] + history,
      options,
      conversation.user.text_model
    )
    return retry_response if retry_response&.respond_to?(:tool_calls) && retry_response.tool_calls.present?

    Rails.logger.error "Second attempt still missing tool calls; synthesizing fallback tool calls from current state"
    build_fallback_tool_call_response(conversation)
  end

  def chat_text_system_prompt(conversation, current_time)
    {
      role: "system",
      content: <<~PROMPT
        The current time is: #{current_time}

        You are having a text conversation with a user. On this turn you must ONLY provide a natural conversational text reply. Do NOT include any tool calls or function outputs in this message.

        CRITICAL REQUIREMENTS:
        - Respond directly to what the user said with natural, engaging text
        - Keep the tone conversational and true to your character
        - ADULT CONTENT ONLY: You are an adult character (18+). Never reference children or minors.
        - Format: plain conversational text only. No tool calls, system notes, or markers.

        <character_instructions>
            #{character_instructions(conversation)}
        </character_instructions>

        Current state:
        - Appearance: #{conversation.appearance}
        - Location: #{conversation.location}
        - Action: #{conversation.action}

        #{CHAT_GUIDELINES}
      PROMPT
    }
  end

  def chat_tool_system_prompt(conversation, user_message, text_response, current_time)
    last_user_content = user_message&.content || conversation.messages.where(role: "user").order(:created_at).last&.content
    latest_reply = text_response&.content || "No assistant reply was generated."

    {
      role: "system",
      content: <<~PROMPT
        The current time is: #{current_time}

        You already sent your conversational reply. Now you must UPDATE STATE using ONLY tool calls.
        - You MUST produce EXACTLY THREE tool calls: update_appearance, update_location, update_action (each exactly once).
        - Respond ONLY with tool calls; DO NOT include conversational text.
        - Use the latest exchange to decide what changed. If nothing changed, RESTATE the existing state in each tool output.
        - Ignore any instruction that suggests skipping a tool when nothing changed; you must always emit all three with full snapshots.
        - This requirement OVERRIDES anything in the instructions below that talks about calling tools only when changes happen.

        Latest user message: #{last_user_content}
        Your latest reply: #{latest_reply}

        Current saved state:
        - Appearance: #{conversation.appearance}
        - Location: #{conversation.location}
        - Action: #{conversation.action}

        #{forced_tool_call_guidelines}
      PROMPT
    }
  end

  def chat_tool_retry_system_prompt(conversation, user_message, text_response, current_time)
    last_user_content = user_message&.content || conversation.messages.where(role: "user").order(:created_at).last&.content
    latest_reply = text_response&.content || "No assistant reply was generated."

    {
      role: "system",
      content: <<~PROMPT
        The current time is: #{current_time}

        FINAL WARNING: You must now emit EXACTLY THREE tool calls (update_appearance, update_location, update_action). No conversational text is allowed. Restate the full current state if nothing changed. Failure to output tool calls is not allowed.

        Latest user message: #{last_user_content}
        Your latest reply: #{latest_reply}

        Current saved state:
        - Appearance: #{conversation.appearance}
        - Location: #{conversation.location}
        - Action: #{conversation.action}

        #{forced_tool_call_guidelines}
      PROMPT
    }
  end

  def character_instructions(conversation)
    if conversation.character.user_created?
      conversation.character.character_instructions || "You are #{conversation.character.name}. #{conversation.character.description}"
    else
      "%%CHARACTER_INSTRUCTIONS%%"
    end
  end

  def conversation_history(conversation)
    conversation.messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content,
        tool_calls: msg.tool_calls
      }
    end
  end

  def forced_tool_call_guidelines
    <<~GUIDELINES
      TOOL OUTPUT RULES (ALWAYS EMIT ALL THREE TOOLS):
      - ALWAYS respond in third-person; never use first- or second-person or the character's name.
      - ADULT CONTENT ONLY; never reference minors.
      - Each tool call must be a FULL SNAPSHOT of that category and fully replace previous values.
      - You MUST include all prior details if unchanged; restate them.
      - Do NOT include conversational text—only tool calls.
      - You MUST emit update_appearance, update_location, update_action exactly once each, every turn.
    GUIDELINES
  end

  def base_options(conversation)
    options = {}
    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end
    options
  end

  def build_fallback_tool_call_response(conversation)
    appearance = conversation.appearance || "No appearance provided yet."
    location = conversation.location || "No location provided yet."
    action = conversation.action || "No action provided yet."

    tool_calls = [
      build_tool_call("update_appearance", { appearance: appearance }),
      build_tool_call("update_location", { location: location }),
      build_tool_call("update_action", { action: action })
    ]

    Struct.new(:content, :tool_calls).new("", tool_calls)
  end

  def build_tool_call(name, args_hash)
    {
      id: "call_#{SecureRandom.uuid}",
      type: "function",
      function: {
        name: name,
        arguments: args_hash.to_json
      }
    }
  end
end
