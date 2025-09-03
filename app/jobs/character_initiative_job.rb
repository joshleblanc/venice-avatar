class CharacterInitiativeJob < ApplicationJob
  queue_as :default
  
  def perform(conversation)
    return unless conversation&.persisted?
    return if conversation.character_away?
    return if conversation.generating_reply?
    
    # Check if there's already a recent initiative message to avoid spam
    recent_initiative = conversation.messages
                                  .where(role: 'assistant')
                                  .where("metadata->>'initiative' = 'true'")
                                  .where('created_at > ?', 10.minutes.ago)
                                  .exists?
    
    return if recent_initiative
    
    # Find applicable schedules for this character
    applicable_schedules = conversation.character
                                     .character_schedules
                                     .active
                                     .by_priority
                                     .select { |schedule| schedule.should_trigger?(conversation) }
    
    return if applicable_schedules.empty?
    
    # Use the highest priority schedule that should trigger
    schedule = applicable_schedules.first
    
    Rails.logger.info "Character initiative triggered for conversation #{conversation.id} using schedule #{schedule.id}"
    
    # Check if user is currently in an active conversation to avoid interruption
    return if conversation_in_progress?(conversation)
    
    # Generate and send initiative message
    begin
      conversation.update(generating_reply: true)
      
      message_content = schedule.generate_initiative_message(conversation)
      
      # Create the initiative message
      message = conversation.messages.create!(
        content: message_content,
        role: 'assistant',
        user: conversation.user,
        metadata: {
          initiative: true,
          initiative_schedule_id: schedule.id,
          initiative_type: schedule.schedule_type,
          auto_generated: true
        }
      )
      
      # Evolve scene prompt if needed
      prompt_service = AiPromptGenerationService.new(conversation)
      current_prompt = prompt_service.get_current_scene_prompt
      EvolveScenePromptJob.perform_later(conversation, message, current_prompt)
      
      # Generate scene images
      GenerateImagesJob.perform_later(conversation)
      
      Rails.logger.info "Character initiative message sent for conversation #{conversation.id}"
      
    rescue => e
      Rails.logger.error "Failed to send character initiative message: #{e.message}"
    ensure
      conversation.update(generating_reply: false)
    end
  end
  
  private
  
  def conversation_in_progress?(conversation)
    # Check if user has sent a message recently (within last 2 minutes)
    # This indicates they might be actively typing or engaged
    recent_user_message = conversation.messages
                                    .where(role: 'user')
                                    .where('created_at > ?', 2.minutes.ago)
                                    .exists?
    
    recent_user_message
  end
end