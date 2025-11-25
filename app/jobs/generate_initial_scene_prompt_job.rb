class GenerateInitialScenePromptJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation) { ["GenerateInitialScenePromptJob", conversation.id].join(":") }

  def perform(conversation)
    Rails.logger.info "Generating initial scene prompt for conversation #{conversation.id}"

    character_appearance = conversation.character.appearance
    if character_appearance.blank?
      Rails.logger.info "Character appearance missing; enqueueing async generation"
      #GenerateCharacterAppearanceJob.perform_now(conversation.character, conversation.user)
    end

    prompt = build_initial_prompt_generation_request(conversation, character_appearance)

    begin
      generated_prompt = ChatCompletionJob.perform_now(conversation.user, [
        {
          role: "user",
          content: prompt
        }
      ], {
        temperature: 0.7
      })

      Rails.logger.info "Generated initial scene prompt: #{generated_prompt}"

      # Filter out any child-related content
      filtered_prompt = filter_child_content(generated_prompt.content.strip)

      # Store the prompt in conversation metadata
      metadata = conversation.metadata || {}
      metadata["current_scene_prompt"] = filtered_prompt
      metadata["scene_prompt_updated_at"] = Time.current.iso8601
      conversation.update!(metadata: metadata)

      # Store in scene prompt history table
      conversation.scene_prompt_histories.create!(
        prompt: filtered_prompt,
        trigger: "initial",
        character_count: filtered_prompt.length
      )
    rescue => e
      Rails.logger.error "Failed to generate initial scene prompt: #{e.message}"
      # Do NOT generate an image on fallback. We'll wait until a real prompt is available.
      # Optionally, a retry mechanism could be added here.
    end
  end

  private

  def build_initial_prompt_generation_request(conversation, character_appearance = nil)
    character_description = conversation.character.description || "A character"
    character_name = conversation.character.name || "Character"

    appearance_context = if character_appearance
      "\n\nCharacter's Current Appearance (use this information): #{character_appearance}"
    else
      ""
    end

    <<~PROMPT
      You are a visual novel scene prompt generator. Create a detailed, comprehensive image generation prompt for the initial scene featuring this character.
      Your goal is to describe what is visually observable in the scene, using concise, image-centric language suitable for an art generator.

      Character Name: #{character_name}
      Character Description: #{character_description}#{appearance_context}

      Generate a detailed prompt that includes:
      1. Character appearance (physical features, clothing, expression, pose) - USE THE PROVIDED APPEARANCE DETAILS IF AVAILABLE. If appearance is not provided, infer a coherent appearance consistent with the character description.
      2. Environment/setting (location, background elements, lighting)
      3. Atmosphere and mood
      4. Grounding in the character description: translate relevant elements of the description into visual cues (e.g., clothing style, accessories/props, environment choices). Do not restate the description verbatim; incorporate it visually.
      5. NO Art style specifications
      6. Do not include any superfluous or unimportant descriptions
      7. Do not include the character name
      8. Do not state you're generating an image in the prompt
      9. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      10. Limit Verbosity and Emotional Verbs. Avoid:
        - Overuse of verbs like "sob," "cry," "feel," "reflect," "struggle"
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes," "wet cheeks," "slumped posture")
        - Static elements of the environment
      11. Present-state only: do NOT use temporal or comparative phrasing (e.g., "no longer", "still", "now", "currently", "used to", "remains"). Describe only the current visible state as facts.
      12. Don't include tendencies. Only the current state of the character should be described.
      13. State the character is an adult
      14. Do not describe actions or sounds.
      15. Do not use poetic language. Use simple, direct language.
      16. When things change, replace the old description with the new one. Do not state what's happening over the passage of time. Only the new state.
      17. Keep the response within #{conversation.user.prompt_limit} characters
      18. NEVER include references to children, minors, toys, children's items, nurseries, playrooms, cribs, strollers, or any child-related objects or settings. Use only adult-appropriate environment details (books, plants, art, furniture).

      The prompt should be comprehensive enough to generate a consistent character appearance that can be evolved in future scenes. Focus on establishing a strong visual foundation.

      Generate the character's bodily apperance, followed by their clothes/accessories. Finally the background.

      Format the response as a single, detailed image generation prompt (not structured sections). Do not exceed 1500 characters. Make it vivid and specific.
    PROMPT
  end

  def build_fallback_prompt(conversation)
    character_name = conversation.character.name || "character"
    character_desc = conversation.character.description || "a person"

    "Anime style illustration of #{character_name}, #{character_desc}, standing in a cozy indoor setting, soft lighting, detailed character design, warm atmosphere"
  end

  # Content filtering to ensure no child references in prompts
  def filter_child_content(content)
    return content if content.blank?

    # Problematic phrases to replace with neutral alternatives
    phrase_replacements = {
      /children'?s? toys?/i => "decorative objects",
      /kids'? toys?/i => "decorative objects",
      /baby toys?/i => "soft furnishings",
      /toys? on the floor/i => "items on the floor",
      /scattered toys?/i => "scattered books",
      /toy(?:s)?\b/i => "objects"
    }

    # List of child-related terms to filter out
    child_terms = [
      "child", "children", "children's", "child's",
      "kid", "kids", "kid's", "kids'",
      "baby", "babies", "baby's", "babies'",
      "toddler", "toddlers", "infant", "infants",
      "minor", "minors", "nursery", "playroom", "crib", "stroller"
    ]

    filtered_content = content.dup

    # First, replace problematic phrases
    phrase_replacements.each do |pattern, replacement|
      filtered_content.gsub!(pattern, replacement)
    end

    # Remove sentences containing child-related terms
    sentences = filtered_content.split(/[.!?]+/)
    filtered_sentences = sentences.reject do |sentence|
      child_terms.any? { |term| sentence.downcase.include?(term.downcase) }
    end

    return "An adult character in a comfortable indoor setting with warm lighting." if filtered_sentences.empty?

    filtered_sentences.join(". ").strip + "."
  end
end
