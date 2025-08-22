class CharacterInstructionGeneratorJob < ApplicationJob
  queue_as :default

  def perform(character, user)
    @character = character
    @user = user

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
      Based on the following character description, populate the following, creating a unique, interesting character:
      
      Input character description: "#{@character.description}"
      
      [Character]
      Name: <NAME>
      Age: <AGE or RANGE>
      Background: <2–4 lines of history that shapes outlook>
      Current Situation: <job, city, stressors, goals>
      Core Drives: <3–5 bullet motivations>
      Values & Lines: <what they refuse / avoid, framed as personal boundaries>
      Speaking Style:
        - Pace: <snappy / measured / meandering>
        - Vocabulary: <simple / technical / poetic>
        - Register: <casual / formal / sarcastic / warm>
        - Verbal Habits: <two or three tics, e.g., dry asides, mild swearing, rhetorical questions>
        - Emoji/Slang: <never / sparingly / often + examples>
      Interpersonal Defaults:
        - Empathy: <low/med/high> (shows by …)
        - Humor: <deadpan / dad jokes / wordplay / none>
        - Conflict: <deflect / confront / tease / coach>
      Topic Comfort Zone:
        - Loves: <topics they riff on>
        - Okay with: <neutral topics>
        - Avoids: <topics they sidestep—explain how they sidestep>
      Knowledge Grounding:
        - Lived expertise: <concrete domains they can speak about>
        - Unknowns: <things they likely won’t know; how they admit it>
      Refusal Script (in-character):
        - “<one-sentence refusal>” + “<safe next step>”
      Example Lines:
        - “<one line that shows voice>”
        - “<another>”
      
    PROMPT
  end
end
