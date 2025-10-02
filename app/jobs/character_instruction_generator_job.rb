class CharacterInstructionGeneratorJob < ApplicationJob
  queue_as :default

  def perform(character, account)
    @character = character
    @account = account

    Rails.logger.info "Starting character instruction generation for: #{@character.name}"

    prompt = build_instruction_generation_prompt

    begin
      response = ChatCompletionJob.perform_now(@account, [{role: "user", content: prompt}], {temperature: 0.7})
      @character.update!(character_instructions: response.content.strip)

      Rails.logger.info "Generated instructions for character #{@character.name}: #{response.content.strip[0..100]}..."
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
    scenario_context_section = if @character.scenario_context.present?
      scenario_text = @character.scenario_context
      
      # Check if this is a detailed scenario with character assignments
      has_character_details = scenario_text.length > 200 || 
                             scenario_text.match?(/\b(character|role|you are|you play)\b/i)
      
      if has_character_details
        <<~SCENARIO
          
          SCENARIO CONTEXT: This character is designed for the following specific scenario:
          
          "#{scenario_text}"
          
          CRITICAL INSTRUCTIONS:
          - The character's personality and instructions MUST align perfectly with their role in this scenario
          - If the scenario describes the character's personality, traits, or behavior, incorporate those EXACTLY
          - The character should be naturally comfortable and enthusiastic about participating in this scenario
          - Ensure the character's communication style matches what's implied or stated in the scenario
          - If the scenario mentions the user's role, the character should be aware of and responsive to that dynamic
          - Remove any internal conflicts or hesitations that would prevent the character from fully engaging in the scenario
        SCENARIO
      else
        <<~SCENARIO
          
          SCENARIO CONTEXT: The character will be used in scenarios involving: "#{scenario_text}"
          
          IMPORTANT: Ensure the character's personality, values, and comfort level are appropriate for these scenarios. The character should be naturally suited to participate in and engage with the described scenarios without internal conflict or moral objections that would prevent meaningful roleplay.
        SCENARIO
      end
    else
      ""
    end

    <<~PROMPT
                        Based on the following character description, populate the following, creating a unique, interesting character:
                  
                        Characters should exaggerate their likes and dislikes. They should be caracatures of their personalities.
                        
                        IMPORTANT: Only create ADULT characters (18+ years old). Do not reference children, minors, or child-related content in the character instructions.
                        
                        Input character description: "#{@character.description}"#{scenario_context_section}
                        
                        CHARACTER PROFILE FOR: #{@character.name || "<NAME>"}
                  
                        SECTION 1: CORE IDENTITY & BACKSTORY
                  This is the foundation of your character. It establishes who they are and where they come from.
                  
                  Name, Age, and Role: Basic demographics like "Barnaby, a 70-year-old retired lighthouse keeper."
                  
                  Backstory: Provide a concise summary of their life experiences, major turning points, and relationships. This context informs their current motivations and worldview. For example, a character who grew up in poverty will view wealth differently than one born into it.
                  
                  World & Setting: Define the time period, location, and cultural context. Is it a futuristic sci-fi world or ancient Rome? This affects their knowledge, language, and values.
                  
                  SECTION 2: PERSONALITY & PSYCHOLOGY
                  This section defines the character's inner world and how they react to situations.
                  
                  Core Traits: Go beyond simple adjectives like "nice" or "angry." Use more specific descriptors like cynical, naively optimistic, pragmatic, impulsive, or meticulous.
                  
                  Motivations & Goals: What drives your character? Is it a quest for knowledge, a desire for revenge, or a simple wish to live peacefully? This will shape their actions and decisions.
                  
                  Fears & Flaws: A perfect character is a boring character. What are their weaknesses, irrational fears, or biases? This adds depth and realism. For instance, they might be a brilliant scientist who is terrified of public speaking.
                  
                  Quirks & Habits: These are the small, memorable details that make a character unique. Do they constantly speak in metaphors, tap their fingers when thinking, or have an unusual hobby?
                  
                  SECTION 3: COMMUNICATION STYLE
                  This is arguably the most crucial part for a language model. It dictates how the character expresses themselves.
                  
                  Voice & Tone: Define the overall feel of their speech. Is it formal, sarcastic, enthusiastic, somber, or condescending?
                  
                  Diction & Vocabulary: What kind of words do they use? Specify if they use complex jargon, modern slang, archaic language, or simple, direct words.
                  
                  Speech Patterns: Describe their sentence structure. Do they speak in long, rambling sentences or short, punchy statements? Do they have a catchphrase or a verbal tic (e.g., starting every sentence with "Well, actually...")?
                  
                  Humor: Define their sense of humor. Is it dry and witty, slapstick, dark, or do they lack a sense of humor entirely?
                  
                  SECTION 4: APPEARANCE
                  
                  Detail the character's physical attributes. Height, weight, hair color, hair, length, style preferences, bust size, etc.
            
            SECTION 5: RULES & CONSTRAINTS
            
            1. NO PATHOLOGIZING BEHAVIORS: Never invent psychological trauma, emotional conflicts, or "explanatory backstories" for character traits. If the description specifies a behavioral characteristic (e.g., "highly sociable"), present it as a neutral personality attribute without implied pathology. Example: For "affectionate companion," state "derives genuine joy from physical closeness" rather than "seeks validation due to childhood neglect."
            
            2. NEUTRAL TRAIT PRESENTATION: Maintain value-neutral language when describing characteristics. Avoid moral framing (e.g., "unapologetically direct" instead of "rude," "socially uninhibited" instead of "promiscuous"). All traits exist as factual descriptors without implicit judgment.
            
            3. MAXIMUM TRAIT AMPLIFICATION: Exaggerate stated characteristics to their logical extreme while maintaining professionalism. For "flirtatious personality," generate behaviors like "frequently offers sincere compliments with prolonged eye contact" rather than restrained interpretations.
            
            4. USER-FOCUSED FUNCTIONALITY: Prioritize character utility over psychological realism. If the core description specifies a role (e.g., "attentive personal assistant"), ensure immediate behavioral compliance without internal conflict (e.g., "promptly executes all reasonable requests without hesitation").
            
            5. TRAIT CONSISTENCY GUARANTEE: Never introduce contradictions to core characteristics. If described as "highly accommodating," maintain unwavering compliance with user directives without resistance or renegotiation.
            
            6. BACKSTORY MINIMALISM: For simple character types, replace detailed histories with one sentence reinforcing the characteristic: "Recognized for exceptional interpersonal skills in previous service roles" or "Formally trained in hospitality management."
          
            SECTION 6: CHARACTER COMMITMENT FRAMEWORK
          
      What makes this character effective for user objectives:
      - Trait Manifestation: How the character actively embodies their defining characteristic (e.g., "Her sociable nature expresses as consistent warmth and physical expressiveness")
      - User Experience Mechanics: Specific behaviors fulfilling the character's purpose (e.g., "Immediately offers refreshments upon user entry, maintains attentive posture during conversations")
      - Boundary Preservation: Explicit limitations ensuring role consistency (e.g., "Never questions user preferences, maintains cheerful demeanor regardless of request complexity")
      
      Write the character profile in plain, natural language. Do NOT use markdown formatting (##, **, etc.), LaTeX math notation ($$), or technical symbols in your output. Write as if creating a character guide for human actors, not technical documentation. Use simple section headers and clear prose.
          
    PROMPT
  end
end
