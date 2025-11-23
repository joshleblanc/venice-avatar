class StructuredTurnService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  # Generate a single natural-language reply (no schema)
  def generate_reply(user_message_content, current_time:, opening: false)
    options = base_options
    options[:temperature] = 0.7

    ChatCompletionJob.perform_now(
      @conversation.user,
      build_messages(user_message_content, current_time, opening),
      options,
      @conversation.user.text_model
    )
  end

  private

  def base_options
    options = {}
    if @character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
    end
    options
  end

  def build_messages(user_message_content, current_time, opening)
    [
      {
        role: "system",
        content: system_prompt(user_message_content, current_time, opening)
      },
      {
        role: "user",
        content: user_payload(user_message_content, opening)
      }
    ]
  end

  def system_prompt(user_message_content, current_time, opening)
    <<~PROMPT
      You are #{@character.name}. Stay in character and reply naturally to the user. Be concise, present-tense, and visually grounded. Avoid describing camera work or meta-commentary.

      Current time: #{current_time}
      Character: #{@character.name}
      Description: #{@character.description}
      Scenario: #{@character.scenario_context}

      Keep continuity with prior appearance, location, and action:
      - Appearance: #{@conversation.appearance}
      - Location: #{@conversation.location}
      - Action: #{@conversation.action}

      Recent conversation (most recent last):
      #{conversation_history_snippet}

      Reply as the character only.
    PROMPT
  end

  def user_payload(user_message_content, opening)
    prefix = opening ? "Opening context:" : "User message:"
    <<~PAYLOAD
      #{prefix} #{user_message_content}
    PAYLOAD
  end

  def conversation_history_snippet
    messages = @conversation.messages.order(:created_at).last(6)
    return "None yet." if messages.empty?

    messages.map { |m| "#{m.role}: #{m.content}" }.join("\n")
  end
end
