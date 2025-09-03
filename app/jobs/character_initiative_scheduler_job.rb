class CharacterInitiativeSchedulerJob < ApplicationJob
  queue_as :default
  
  # This job runs periodically to check all active conversations
  # and trigger character initiatives when appropriate
  def perform
    Rails.logger.info "Running character initiative scheduler"
    
    # Find all active conversations (updated within last 7 days)
    active_conversations = Conversation.joins(:character)
                                     .where('conversations.updated_at > ?', 7.days.ago)
                                     .where(character_away: false)
                                     .where(generating_reply: false)
                                     .includes(:character, :messages)
    
    Rails.logger.info "Checking #{active_conversations.count} active conversations for character initiatives"
    
    active_conversations.find_each do |conversation|
      begin
        # Check if any character schedules should trigger for this conversation
        should_trigger = conversation.character
                                   .character_schedules
                                   .active
                                   .any? { |schedule| schedule.should_trigger?(conversation) }
        
        if should_trigger
          Rails.logger.info "Scheduling character initiative for conversation #{conversation.id}"
          CharacterInitiativeJob.perform_later(conversation)
        end
        
      rescue => e
        Rails.logger.error "Error checking character initiative for conversation #{conversation.id}: #{e.message}"
      end
    end
    
    # Schedule the next run (every 5 minutes)
    CharacterInitiativeSchedulerJob.set(wait: 5.minutes).perform_later
  end
end