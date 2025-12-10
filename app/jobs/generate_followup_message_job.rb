class GenerateFollowupMessageJob < ApplicationJob
  queue_as :default

  def perform(conversation, followup_context)
    # Check if conversation still exists and is valid
    return unless conversation&.persisted?

    # Check if there's already a more recent message (user might have sent something)
    last_message = conversation.messages.order(:created_at).last
    return if last_message&.role == "user" && last_message.created_at > 1.minute.ago

    # Mark any pending follow-ups as completed
    conversation.messages.where(has_pending_followup: true).update_all(has_pending_followup: false)

    conversation.update(generating_reply: true)

    begin
      # Generate follow-up message using Venice API
      chat_response = send_followup_to_venice_chat(conversation, followup_context)

      # Save assistant follow-up message
      assistant_msg = conversation.messages.create!(
        content: chat_response.content.strip,
        role: "assistant",
        user: conversation.user
      )

      # Evolve the scene prompt based on the follow-up message
      current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")
      previous_prompt = conversation.metadata&.dig("current_scene_prompt")
      prompt = ScenePromptService.new(conversation).generate_prompt(
        "",
        chat_response.content.strip,
        current_time: current_time,
        previous_prompt: previous_prompt
      )

      if prompt.present?
        AiPromptGenerationService.new(conversation).store_scene_prompt(prompt, trigger: "followup")
        GenerateImagesJob.perform_later(conversation, prompt)
      end

      # For now, we don't chain follow-ups from follow-up messages to keep it simple
      # This prevents infinite follow-up loops
    rescue => e
      Rails.logger.error "Venice API error in GenerateFollowupMessageJob: #{e.message}"

      # Create a simple follow-up message as fallback
      conversation.messages.create!(
        content: "Error generating follow-up message: #{e.message}",
        role: "assistant",
        user: conversation.user
      )
    ensure
      conversation.update(generating_reply: false)
    end
  end

  private

  def send_followup_to_venice_chat(conversation, followup_context)
    # Build conversation history for context
    messages = conversation.messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.full_content_for_ai
      }
    end

    # Add context about the follow-up with text messaging context
    system_message = {
      role: "system",
      content: "You are texting with the user remotely via text messages on their phone. " \
               "The user can see you through their phone camera, but you are not physically in the same room. " \
               "Respond as if you're sending text messages - keep responses conversational and natural for texting. " \
               "The user is looking at you through their phone screen while you text back and forth. " \
               "The character previously indicated they would return after: #{followup_context[:context]}. " \
               "Generate a natural follow-up message showing the character returning or continuing the conversation. " \
               "Reason for follow-up: #{followup_context[:reason]}"
    }

    options = {}
    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end

    ChatCompletionJob.perform_now(conversation.user, [ system_message ] + messages, options, conversation.user.text_model) || "I'm back!"
  end

  def schedule_followup_message(conversation, message, followup_intent)
    delay_minutes = followup_intent[:estimated_delay_minutes] || 5
    scheduled_time = delay_minutes.minutes.from_now

    message.update!(
      has_pending_followup: true,
      followup_scheduled_at: scheduled_time,
      followup_context: followup_intent[:context],
      followup_reason: followup_intent[:reason]
    )

    # Schedule the next follow-up job
    GenerateFollowupMessageJob.set(wait_until: scheduled_time)
      .perform_later(conversation, followup_intent)

    Rails.logger.info "Scheduled follow-up message for conversation #{conversation.id} at #{scheduled_time}"
  end
end
