class AiPromptGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @venice_client = VeniceClient::ChatApi.new
  end

  # Generate initial detailed scene prompt when conversation starts
  def generate_initial_scene_prompt
    Rails.logger.info "Generating initial scene prompt for character: #{@character.name}"

    prompt = build_initial_prompt_generation_request

    begin
      response = @venice_client.create_chat_completion({
        body: {
          model: "venice-uncensored",
          messages: [
            {
              role: "user",
              content: prompt,
            },
          ],
          max_completion_tokens: 1500,
          temperature: 0.7,
        },
      })

      generated_prompt = response.choices.first[:message][:content].strip
      Rails.logger.info "Generated initial scene prompt: #{generated_prompt}"

      # Store the prompt in the conversation or character state
      store_scene_prompt(generated_prompt)

      generated_prompt
    rescue => e
      Rails.logger.error "Failed to generate initial scene prompt: #{e.message}"
      # Fallback to basic prompt
      fallback_initial_prompt
    end
  end

  # Evolve the scene prompt based on new message content
  def evolve_scene_prompt(previous_prompt, new_message_content)
    Rails.logger.info "Evolving scene prompt based on new message"

    prompt = build_prompt_evolution_request(previous_prompt, new_message_content)

    begin
      response = @venice_client.create_chat_completion({
        body: {
          model: "venice-uncensored",
          messages: [
            {
              role: "user",
              content: prompt,
            },
          ],
          max_completion_tokens: 1500,
          temperature: 0.3,  # Lower temperature for consistency
        },
      })

      evolved_prompt = response.choices.first[:message][:content].strip
      Rails.logger.info "Evolved scene prompt: #{evolved_prompt}"

      # Store the updated prompt
      store_scene_prompt(evolved_prompt)

      evolved_prompt
    rescue => e
      Rails.logger.error "Failed to evolve scene prompt: #{e.message}"
      # Fallback to previous prompt
      previous_prompt
    end
  end

  # Get the current scene prompt for image generation
  def get_current_scene_prompt
    # Try to get from conversation metadata first
    if @conversation.metadata.present? && @conversation.metadata["current_scene_prompt"]
      return @conversation.metadata["current_scene_prompt"]
    end

    # If no prompt exists, generate initial one
    generate_initial_scene_prompt
  end

  private

  def build_initial_prompt_generation_request
    character_description = @character.description || "A character"
    character_name = @character.name || "Character"

    <<~PROMPT
      You are a visual novel scene prompt generator. Create a detailed, comprehensive image generation prompt for the initial scene featuring this character:
      You are a visual prompt generator. Your goal is to describe what is visually observable in the scene, using concise, image-centric language suitable for an art generator
      
      Character Name: #{character_name}
      Character Description: #{character_description}

      Generate a detailed prompt that includes:
      1. Character appearance (physical features, clothing, expression, pose)
      2. Environment/setting (location, background elements, lighting)
      3. Atmosphere and mood
      4. Art style specifications (anime/visual novel style)
      5. No not include any superfluous, unimportant descriptions.
      6. Do not include the character name
      7. Do not state you're generating an image in the prompt
      8. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      9. Limit Verbosity and Emotional Verbs Ask the model to avoid:
        - Overuse of verbs like "sob," "cry," "feel," "reflect," "struggle"
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes," "wet cheeks," "slumped posture")
        - Static elements of the environment
      10. Don't include tendencies. Only the current state of the character should be described.
      11. The characters are all observably adults

      The prompt should be comprehensive enough to generate a consistent character appearance that can be evolved in future scenes. Focus on establishing a strong visual foundation.

      Format the response as a single, detailed image generation prompt (not structured sections). Do not exceed 1500 characters. Make it vivid and specific. 
    PROMPT
  end

  def build_prompt_evolution_request(previous_prompt, new_message_content)
    <<~PROMPT
      You are a visual novel scene prompt evolution specialist. You need to update an existing scene prompt based on new story content.

      PREVIOUS SCENE PROMPT:
      #{previous_prompt}

      NEW MESSAGE CONTENT:
      #{new_message_content}

      Analyze the new message content and update the scene prompt with MINIMAL changes to reflect:
      - Any mentioned location changes
      - Character expression or emotion changes
      - Clothing or appearance changes
      - New environmental elements
      - Pose or activity changes

      IMPORTANT RULES:
      1. Keep the character's core appearance consistent (don't change fundamental features)
      2. Only modify elements that are explicitly mentioned or strongly implied in the new message
      3. Maintain the same art style and quality specifications
      4. If no visual changes are needed, return the previous prompt unchanged
      5. Make changes subtle and natural - avoid dramatic shifts
      6. Changes to the character should replace the previous character description. For example, if the previous prompt says the character is sad, and the new message says she's screaming in rage, the description of her being sad should be replaced. The new emotion should not be appended.
      7. Describe the visual elements only. Do not include inner thoughts or emotional backstories.
      8. Limit Verbosity and Emotional Verbs Ask the model to avoid:
        - Overuse of verbs like “sob,” “cry,” “feel,” “reflect,” “struggle”
        - Internal states or psychological exposition
        Instead, lean on:
        - Physical cues ("red eyes", "wet cheeks", "slumped posture")
        - Static elements of the environment

      Return the updated prompt as a single, detailed image generation prompt in under 1500 characters.
    PROMPT
  end

  def store_scene_prompt(prompt)
    # Store in conversation metadata
    metadata = @conversation.metadata || {}
    metadata["current_scene_prompt"] = prompt
    metadata["scene_prompt_updated_at"] = Time.current.iso8601

    @conversation.update!(metadata: metadata)
  end

  def fallback_initial_prompt
    character_name = @character.name || "character"
    character_desc = @character.description || "a person"

    "Anime style illustration of #{character_name}, #{character_desc}, standing in a cozy indoor setting, soft lighting, high quality visual novel art style, detailed character design, warm atmosphere"
  end
end
