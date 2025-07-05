class CharacterReturnJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    # Only proceed if character is still away and there are queued user messages
    return unless conversation.character_away?

    # Check if there are any user messages waiting
    brb_message = conversation.messages.where(role: "assistant")
                              .where("metadata LIKE ?", "%auto_generated%")
                              .order(:created_at).last

    return unless brb_message

    queued_messages = conversation.messages.where(role: "user")
                                  .where("created_at > ?", brb_message.created_at)
                                  .order(:created_at)

    if queued_messages.any?
      Rails.logger.info "Character returning for conversation #{conversation.id}, processing #{queued_messages.count} queued messages"

      # Mark character as no longer away
      conversation.update!(character_away: false)

      # Process all queued messages with a single contextual reply
      # We'll use the most recent user message as the trigger
      latest_user_message = queued_messages.last
      GenerateReplyJob.perform_later(conversation, latest_user_message)
    else
      Rails.logger.info "Character would return for conversation #{conversation.id}, but no queued messages found"
      # Generate a contextual "I'm back" message referencing what they left to do

      return_message = generate_return_message(conversation, brb_message)
      conversation.messages.create!(
        content: return_message,
        role: "assistant",
        metadata: { auto_generated: true, return_message: true },
        user: conversation.user,
      )
      # Mark character as no longer away
      conversation.update!(character_away: false)
      prompt_service = AiPromptGenerationService.new(conversation)
      current_prompt = prompt_service.get_current_scene_prompt
      evolved_prompt = prompt_service.evolve_scene_prompt(current_prompt, return_message)
    end

    GenerateImagesJob.perform_later(conversation)
  end

  private

  def generate_return_message(conversation, brb_message)
    # Get the reason why the character left from the message metadata
    metadata = brb_message.metadata || {}
    reason = metadata["reason"] || metadata[:reason] || "step away"

    # Get recent conversation context for the return message
    recent_messages = conversation.messages.order(:created_at).last(5)
    context = recent_messages.map { |msg| "#{msg.role}: #{msg.content}" }.join("\n")

    # Generate contextual return message using Venice API
    begin
      prompt = <<~PROMPT
        You are #{conversation.character.name} returning from stepping away. You left because: #{reason}
        
        Recent conversation context:
        #{context}
        
        Generate a brief, natural return message (1-2 sentences max) that:
        1. Acknowledges you're back
        2. References what you left to do (#{reason})
        3. Matches your character's personality and speaking style
        4. Feels conversational and natural
        
        Examples:
        - "I'm back! Just finished changing into something more comfortable."
        - "Hey! Got what I needed from the kitchen."
        - "I'm back! That took longer than expected."
        
        Generate ONLY the return message, no quotes or extra text:
      PROMPT

      return_message = ChatCompletionJob.perform_now(conversation.user, [{ role: "user", content: prompt }], { max_completion_tokens: 100, temperature: 0.8 })

      Rails.logger.info "Generated contextual return message: #{return_message}"

      return_message
    rescue => e
      Rails.logger.error "Failed to generate return message via Venice API: #{e.message}"

      # Fallback to simple contextual message
      case reason.downcase
      when /change|clothes|outfit/
        "I'm back! Just finished changing."
      when /grab|get|fetch/
        "I'm back! Got what I needed."
      when /check|look/
        "I'm back! All taken care of."
      when /bathroom|restroom/
        "I'm back!"
      when /kitchen|food|drink/
        "I'm back! Just grabbed something from the kitchen."
      else
        "I'm back! Sorry for stepping away."
      end
    end
  end
end
