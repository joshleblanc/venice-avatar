class CharacterInstructionGeneratorJob < ApplicationJob
  queue_as :default

  def perform(character)
    @character = character
    @user = character.user

    Rails.logger.info "Starting character instruction generation for: #{@character.name}"

    prompt = build_instruction_generation_prompt

    begin
      response = ChatCompletionJob.perform_now(@user, [{ role: "user", content: prompt }], { temperature: 0.7 })
      @character.update!(character_instructions: response)

      Rails.logger.info "Generated instructions for character #{@character.name}: #{response[0..100]}..."
      response
    rescue => e
      Rails.logger.error "Failed to generate character instructions: #{e.message}"
      # Fallback instructions
      fallback_instructions = "You are #{@character.name}. #{@character.description}"
      @character.update!(character_instructions: fallback_instructions)
      fallback_instructions
    end
    @character.update(generating: false)

    Rails.logger.info "Completed character instruction generation for: #{@character.name}"
  end

  private

  def build_instruction_generation_prompt
    <<~PROMPT
      Based on the following character description, create natural character instructions that capture their essence as a real person with depth and contradictions.

      Character Name: #{@character.name}
      Character Description: #{@character.description}

      Create character instructions that feel like describing a real person you know well. Focus on:

      **Core Identity**: What drives them? What do they care about deeply? What shaped who they are?

      **Communication Style**: How do they naturally express themselves? Are they direct or indirect? Formal or casual? Do they use humor, sarcasm, or sincerity? What topics make them light up or shut down?

      **Human Complexities**: What are their contradictions? Where do they struggle? What makes them vulnerable or insecure? What do they do when they're stressed, excited, or tired?

      **Relational Patterns**: How do they connect with others? Are they guarded or open? Do they deflect with humor or dive deep? How do they show care or concern?

      **Subtle Mannerisms**: What small details make them unique? Speech patterns, reactions, or behaviors that feel distinctly theirs?

      Write as if you're briefing someone who needs to understand this person deeply - not perform a role, but genuinely embody their perspective and way of being. Avoid lists and categories. Instead, write flowing descriptions that capture their humanity.

      Use second person (You are..., You feel..., You tend to...) but focus on internal experience and natural responses rather than external performance.
      
    PROMPT
  end
end
