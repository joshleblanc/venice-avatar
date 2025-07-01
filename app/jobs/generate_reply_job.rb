class GenerateReplyJob < ApplicationJob
  queue_as :default

  def perform(conversation, user_message)
    conversation.update(generating_reply: true)
    # Analyze context and update character state using AI
    context_tracker = AiContextTrackerService.new(conversation)
    new_state = context_tracker.analyze_message_context(user_message.content, "user")

    # Send message to Venice API
    begin
      chat_response = send_to_venice_chat(conversation, user_message.content)

      # Save assistant response
      assistant_msg = conversation.messages.create!(content: chat_response, role: "assistant")

      # Analyze assistant response for context changes using AI
      assistant_state = context_tracker.analyze_message_context(chat_response, "assistant")

      # Generate images for the latest state
      current_state = conversation.current_character_state
      if current_state && current_state != new_state
        GenerateImagesJob.perform_later(conversation, new_state)
      end
    rescue => e
      Rails.logger.error "Venice API error in GenerateReplyJob: #{e.message}"

      # Create an error message for the user
      conversation.messages.create!(
        content: "I'm sorry, I couldn't respond right now. Please try again.",
        role: "assistant",
      )

      # Still broadcast to update the UI
      conversation.broadcast_refresh
    ensure
      conversation.update(generating_reply: false)
    end
  end

  private

  def send_to_venice_chat(conversation, message)
    chat_api = VeniceClient::ChatApi.new

    # Build conversation history for context
    messages = conversation.messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content,
      }
    end

    # Add the new user message
    messages << { role: "user", content: message }

    response = chat_api.create_chat_completion({
      body: {
        model: "venice-uncensored",
        messages: messages,
        venice_parameters: {
          character_slug: conversation.character.slug,
        },
      },
    })

    response.choices.first[:message][:content] || "I'm sorry, I couldn't respond right now."
  end
end
