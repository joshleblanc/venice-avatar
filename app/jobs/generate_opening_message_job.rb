# Simplified opening message job:
# 1. Generate plain text opening reply
# 2. Generate initial scene prompt
# 3. Generate image
class GenerateOpeningMessageJob < ApplicationJob
  queue_as :default

  def perform(conversation)
    Rails.logger.info "Generating opening message for conversation #{conversation.id}"

    conversation.update(generating_reply: true)
    current_time = Time.current.strftime("%A, %B %d, %Y at %I:%M %p %Z")

    begin
      # Step 1: Generate opening reply
      opening_context = build_opening_context(conversation)
      service = StructuredTurnService.new(conversation)
      reply_text = service.generate_reply(opening_context, current_time: current_time, opening: true)

      # Step 2: Save the assistant message
      assistant_message = conversation.messages.create!(
        content: reply_text.presence || "Hello!",
        role: "assistant",
        user: conversation.user
      )

      # Step 3: Generate scene prompt
      previous_prompt = conversation.metadata&.dig("current_scene_prompt")
      prompt = ScenePromptService.new(conversation).generate_prompt(
        opening_context,
        reply_text,
        current_time: current_time,
        previous_prompt: previous_prompt
      )

      # Step 4: Store and generate image
      if prompt.present?
        AiPromptGenerationService.new(conversation).store_scene_prompt(prompt, trigger: "opening")
        GenerateImagesJob.perform_later(conversation, prompt)
      end
    rescue => e
      Rails.logger.error "Failed to generate opening message: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      conversation.messages.create!(
        content: "Hello! Nice to meet you.",
        role: "assistant",
        user: conversation.user
      )
    ensure
      conversation.update(generating_reply: false)
    end
  end

  private

  def build_opening_context(conversation)
    character = conversation.character
    <<~PROMPT
      You are #{character.name}. #{character.description}
      #{character.scenario_context.presence}

      You're initiating a conversation with someone new. Greet them naturally as your character.
    PROMPT
  end
end
