class CharacterInstructionGeneratorJob < ApplicationJob
  queue_as :default

  def perform(character)
    Rails.logger.info "Starting character instruction generation for: #{character.name}"
    
    service = CharacterInstructionGeneratorService.new(character)
    service.generate_instructions
    
    Rails.logger.info "Completed character instruction generation for: #{character.name}"
  end
end
