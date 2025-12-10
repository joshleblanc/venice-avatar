# Simplified service that generates plain text replies without tool calls.
# Scene prompt evolution is handled separately by ScenePromptService.
class StructuredTurnService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  # Generate a plain text reply from the character
  # @param user_message_content [String] The user's message
  # @param current_time [String] Current time for context
  # @param opening [Boolean] Whether this is an opening message
  # @return [String] The character's reply text
  def generate_reply(user_message_content, current_time:, opening: false)
    options = base_options
    options[:temperature] = 0.7

    response = ChatCompletionJob.perform_now(
      @conversation.user,
      build_messages(user_message_content, current_time, opening),
      options,
      @conversation.user.text_model
    )

    response&.content.to_s.strip
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
    messages = []

    # System prompt
    messages << {
      role: "system",
      content: system_prompt(current_time)
    }

    # Include recent conversation history
    @conversation.messages.order(:created_at).last(10).each do |msg|
      messages << { role: msg.role, content: msg.content }
    end

    # Current user message
    messages << {
      role: "user",
      content: user_message_content
    }

    messages
  end

  def system_prompt(current_time)
    <<~PROMPT
      You are #{@character.name}. Stay in character and reply naturally.

      #{@character.character_instructions.presence || @character.description}

      #{@character.scenario_context.presence}

      Current time: #{current_time}

      Reply conversationally as the character. Be engaging and natural.
    PROMPT
  end
end
