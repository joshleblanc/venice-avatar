class GenerateInitialScenePromptJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation) { ["GenerateInitialScenePromptJob", conversation.id].join(":") }

  def perform(conversation)
    Rails.logger.info "Generating initial scene prompt for conversation #{conversation.id}"
    
    character_appearance = conversation.character.appearance
    if character_appearance.blank?
      Rails.logger.info "Character appearance missing; enqueueing async generation"
      GenerateCharacterAppearanceJob.perform_later(conversation.character)
    end
    
    prompt = build_initial_prompt_generation_request(conversation, character_appearance)

    begin
      generated_prompt = ChatCompletionJob.perform_now(conversation.user, [
        {
          role: "user",
          content: prompt,
        },
      ], {
        temperature: 0.7,
      })
      
      normalized = PromptUtils.normalize_tag_list(generated_prompt, max_len: conversation.user.prompt_limit, always_include: ["adult"]) 
      Rails.logger.info "Generated initial scene prompt: #{normalized}"

      # Store the prompt in conversation metadata
      metadata = conversation.metadata || {}
      metadata["current_scene_prompt"] = normalized
      metadata["scene_prompt_updated_at"] = Time.current.iso8601
      conversation.update!(metadata: metadata)

      # Store in scene prompt history table
      conversation.scene_prompt_histories.create!(
        prompt: normalized,
        trigger: "initial",
        character_count: normalized.length,
      )

      # Now that we have the scene prompt, generate the initial scene image
      # Enqueue only once per conversation start
      metadata = conversation.metadata || {}
      if !(metadata["initial_image_enqueued"] || conversation.scene_image.attached? || conversation.scene_generating?)
        metadata["initial_image_enqueued"] = true
        conversation.update!(metadata: metadata)
        GenerateImagesJob.perform_later(conversation)
      else
        Rails.logger.info "Initial scene image already enqueued/present; skipping duplicate enqueue"
      end
    rescue => e
      Rails.logger.error "Failed to generate initial scene prompt: #{e.message}"
      # Do NOT generate an image on fallback. We'll wait until a real prompt is available.
      # Optionally, a retry mechanism could be added here.
    end
  end

  private

  def generate_character_appearance(conversation)
    Rails.logger.info "Generating character appearance for scene prompt"
    
    character_instructions = if conversation.character.user_created?
      conversation.character.character_instructions || "You are #{conversation.character.name}. #{conversation.character.description}"
    else
      "%%CHARACTER_INSTRUCTIONS%%"
    end

    appearance_prompt = <<~PROMPT
      Please describe your current appearance in detail. This will help create an accurate visual representation of you. Include:
      
      - What you're currently wearing (clothing, colors, style)
      - Your hair (color, length, style)
      - Your eye color
      - Any accessories you have on
      - Your current expression or mood
      - Your posture or pose
      
      Be specific and detailed, as this information will be used to generate an image of you. Focus only on your physical appearance that would be visible to someone looking at you right now.
    PROMPT

    options = {
      temperature: 0.3,
    }

    if conversation.character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: conversation.character.slug)
    end

    begin
      appearance_details = ChatCompletionJob.perform_now(conversation.user, [
        {
          role: "system",
          content: <<~PROMPT,
            You are the following character:

            <character_instructions>
                #{character_instructions}
            </character_instructions>

            Please describe your current appearance in detail so an accurate visual representation can be created.
          PROMPT
        },
        {
          role: "user",
          content: appearance_prompt,
        }
      ], options)

      # Store appearance on character for future use
      if conversation.character.appearance.blank?
        conversation.character.update!(appearance: appearance_details)
        conversation.character.generate_avatar_later if conversation.character.user.present?
      end

      appearance_details
    rescue => e
      Rails.logger.error "Failed to generate character appearance: #{e.message}"
      nil
    end
  end

  def build_initial_prompt_generation_request(conversation, character_appearance = nil)
    character_description = conversation.character.description || "A character"
    character_name = conversation.character.name || "Character"

    appearance_context = if character_appearance
        "\n\nCharacter's Current Appearance (use this information): #{character_appearance}"
      else
        ""
      end

    <<~PROMPT
      You are a visual prompt generator. Output a single compact, comma-separated tag list (Civitai-style). No sentences. No articles. No character names.

      Character Name: #{character_name}
      Character Description: #{character_description}#{appearance_context}

      Rules:
      - Tags only, lowercase, comma-separated
      - No quotes, parentheses, brackets, colons, or periods
      - Start with subject/appearance, then clothing, expression, pose, environment, lighting, quality
      - Always include: adult
      - Avoid inner thoughts, actions, or sounds
      - Do not list artists, model names, or copyrighted styles
      - Keep under #{conversation.user.prompt_limit} characters

      Return ONLY the tag list, for example:
      1woman, auburn hair, wavy hair, green eyes, beauty mark, natural makeup, rosy lips, tailored suit, crisp blouse, confident posture, standing pose, sunlit office, modern interior, large windows, daylight, soft shadows, focused expression, adult, clean background, sharp focus
    PROMPT
  end

  def build_fallback_prompt(conversation)
    character_name = conversation.character.name || "character"
    character_desc = conversation.character.description || "a person"

    "Anime style illustration of #{character_name}, #{character_desc}, standing in a cozy indoor setting, soft lighting, detailed character design, warm atmosphere"
  end
end
