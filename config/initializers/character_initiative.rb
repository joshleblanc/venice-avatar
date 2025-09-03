# Character Initiative System Initializer
Rails.application.configure do
  # Start the character initiative scheduler after the application boots
  config.after_initialize do
    if Rails.env.production? || Rails.env.development?
      # Start the scheduler job if it's not already running
      # This will run every 5 minutes to check for character initiatives
      begin
        CharacterInitiativeSchedulerJob.perform_later
        Rails.logger.info "Character initiative scheduler started"
      rescue => e
        Rails.logger.error "Failed to start character initiative scheduler: #{e.message}"
      end
    end
  end
end