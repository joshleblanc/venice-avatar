class GenerateReplyJob < ApplicationJob
  queue_as :default

  def perform(conversation, user_message)
    # Don't generate replies if character is away (this shouldn't happen, but safety check)
    if conversation.character_away?
      Rails.logger.info "Character is away, skipping reply generation for conversation #{conversation.id}"
      return
    end

    conversation.update(generating_reply: true)

    # Check if this is the character "returning" from being away
    # In this case, we need to process all queued user messages since the character went away
    messages_to_process = if character_should_return?(conversation)
        get_queued_user_messages_since_character_away(conversation)
      else
        [user_message]
      end

    # Evolve the scene prompt based on all messages to process
    prompt_service = AiPromptGenerationService.new(conversation)
    current_prompt = prompt_service.get_current_scene_prompt
    first_prompt = current_prompt

    # # Process all queued messages to evolve the prompt
    # messages_to_process.each do |msg|
    #   current_prompt = prompt_service.evolve_scene_prompt(current_prompt, msg.content, msg.created_at)
    #   Rails.logger.info "Scene prompt evolved after processing message: #{msg.content[0..50]}..."
    # end

    # Send message to Venice API with contextual awareness of all processed messages
    begin
      # Use the most recent user message for the chat, but the context includes all queued messages
      chat_response = send_to_venice_chat(conversation, user_message.content)

      # Save assistant response
      assistant_msg = conversation.messages.create!(content: chat_response, role: "assistant", user: conversation.user)

      # Check if the character wants to step away after this message
      followup_detector = FollowupIntentDetectorService.new(conversation)
      followup_intent = followup_detector.detect_character_followup_intent(chat_response)

      if followup_intent[:has_intent] && followup_intent[:duration].to_i > 0
        # Character wants to step away - mark the original message as autogenerated and set character as away
        assistant_msg.update!(
          metadata: { auto_generated: true, reason: followup_intent[:reason] },
        )
        conversation.update!(character_away: true)
        Rails.logger.info "Character stepping away for conversation #{conversation.id}: #{followup_intent[:reason]}"

        # Schedule the character to return after a brief delay
        CharacterReturnJob.set(wait: followup_intent[:duration].to_i.seconds).perform_later(conversation)
      end

      # Evolve the scene prompt based on the new assistant message
      prompt_service = AiPromptGenerationService.new(conversation)
      current_prompt = prompt_service.get_current_scene_prompt
      evolved_prompt = prompt_service.evolve_scene_prompt(current_prompt, chat_response, assistant_msg.created_at)
      Rails.logger.info "Scene prompt evolved after assistant message"

      # Generate images for the latest state if prompt changed
      if evolved_prompt != first_prompt
        GenerateImagesJob.perform_later(conversation)
      end
    rescue => e
      Rails.logger.error "Venice API error in GenerateReplyJob: #{e.message}"

      # Create an error message for the user
      conversation.messages.create!(
        content: "I'm sorry, I couldn't respond right now. Please try again.",
        role: "assistant",
        user: conversation.user,
      )
    ensure
      conversation.update(generating_reply: false)
    end
  end

  private

  def send_to_venice_chat(conversation, message)
    # Add system message to establish text messaging context with time awareness
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    # Use different character instruction sources based on character type
    character_instructions = if conversation.character.user_created?
        conversation.character.character_instructions || "You are #{conversation.character.name}. #{conversation.character.description}"
      else
        "%%CHARACTER_INSTRUCTIONS%%"  # Venice will replace this with their character data
      end

    system_message = {
      role: "system",
      content: <<~PROMPT,
        The current time is: #{current_time}

        The assistant is the following character:

        <character_instructions>
            #{character_instructions}
        </character_instructions>

        Here are some additional facts about the assistant:
        - The user can see it through their phone camera, but it is not physically in the same room. 
        - Respond as if it's sending text messages - keep responses conversational and natural for texting. 
        - The user is looking at it through their phone screen while it texts back and forth. 
        - It cannot meet. This is a remote conversation, it does not live close by. 
        - IMPORTANT: Pay attention to the timestamps of messages to understand the passage of time. 
          If significant time has passed between messages (hours, overnight, days), acknowledge this naturally. 
          It might change clothes, location, or reference what it's been doing during the time gap. 
        - It indicates what actions it's taking by surrounding the action with asterisks (*goes to get something*).
        - Describe actions in great detail
        - Do not include the time in your message
      PROMPT
    }

    # Build conversation history for context with timestamps
    messages = conversation.messages.order(:created_at).map do |msg|
      timestamp = msg.created_at.strftime("%A, %B %d at %I:%M %p")
      {
        role: msg.role,
        content: "#{msg.content}",
      }
    end

    Rails.logger.info "Sending message to Venice API: #{messages}"

    # Build API request body - only include venice_parameters for Venice characters
    options = {}

    # Only add venice_parameters for Venice-created characters
    if conversation.character.venice_created?
      options[:venice_parameters] = {
        character_slug: conversation.character.slug,
      }
    end

    ChatCompletionJob.perform_now(conversation.user, [system_message] + messages, options) || "I'm sorry, I couldn't respond right now."
  end

  # Check if the character should return from being away
  def character_should_return?(conversation)
    # This method is called when processing a new user message
    # The character should "return" if there are queued user messages waiting
    conversation.character_away? && has_queued_user_messages?(conversation)
  end

  # Check if there are user messages queued while character was away
  def has_queued_user_messages?(conversation)
    return false unless conversation.character_away?

    # Find the last autogenerated assistant message (the one that triggered the character going away)
    autogen_message = conversation.messages.where(role: "assistant")
      .where("metadata LIKE ?", "%auto_generated%")
      .order(:created_at).last

    return false unless autogen_message

    # Check if there are user messages after the autogenerated message
    conversation.messages.where(role: "user")
      .where("created_at > ?", autogen_message.created_at)
      .exists?
  end

  # Get all user messages that were sent while character was away
  def get_queued_user_messages_since_character_away(conversation)
    # Find the last autogenerated assistant message to determine when character went away
    autogen_message = conversation.messages.where(role: "assistant")
      .where("metadata LIKE ?", "%auto_generated%")
      .order(:created_at).last

    if autogen_message
      # Get all user messages since the character's autogenerated message
      conversation.messages.where(role: "user")
        .where("created_at > ?", autogen_message.created_at)
        .order(:created_at)
    else
      # Fallback: just return the current message if no autogenerated message found
      [conversation.messages.where(role: "user").order(:created_at).last].compact
    end
  end

  # Legacy method - kept for backward compatibility but no longer used
  def schedule_followup_message(message, followup_intent)
    # This method is deprecated in favor of the new "brb" system
    Rails.logger.info "schedule_followup_message called but is deprecated - using brb system instead"
  end
end
