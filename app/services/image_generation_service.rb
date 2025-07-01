class ImageGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @venice_client = VeniceClient::ImageApi.new
  end

  def generate_scene_image(character_state)
    # Always generate new scene images - don't return early if one exists
    # This allows background generation while showing previous scenes

    prompt = build_unified_scene_prompt(character_state)

    models = [
      "venice-sd35",
      "hidream",
      "fluently-xl",
      "flux-dev", # higher prompt length
      "flux-dev-uncensored-11", # higher prompt length
      "flux-dev-uncensored", # higher prompt length
      "lustify-sdxl",
      "pony-realism",
      "stable-diffusion-3.5",
    ]
    begin
      Rails.logger.info "Generating unified scene image with prompt: #{prompt}"
      response = @venice_client.generate_image({
        body: {
          prompt: prompt,
          style_preset: "Anime",
          negative_prompt: "border, frame, text, watermark, signature, blurry, low quality",
          model: models[4],
          width: 640,  # 16:10 ratio for visual novel scenes
          height: 1024,
          safe_mode: false,
          format: "png",
        },
      })

      # Handle base64 response
      base64_data = response.images.first
      if base64_data
        Rails.logger.info "Received unified scene base64 image data, length: #{base64_data.length}"
        attach_base64_image(character_state, :scene_image, base64_data, "scene.png")

        # Save the character state to ensure attachment is persisted
        if character_state.save
          Rails.logger.info "Character state saved successfully with scene image attachment"
          character_state.scene_image
        else
          Rails.logger.error "Failed to save character state: #{character_state.errors.full_messages}"
          nil
        end
      else
        Rails.logger.error "No base64 scene image data received from Venice API"
        nil
      end
    rescue => e
      Rails.logger.error "Failed to generate scene image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end

  def generate_all_images(character_state)
    scene_image = generate_scene_image(character_state)
    {
      scene_image: scene_image,
    }
  end

  private

  def build_unified_scene_prompt(character_state)
    # Initialize detailed character description if not already done
    character_state.initialize_base_character_description(@character)

    # Initialize detailed background description if not already done
    character_state.initialize_detailed_background_description

    # Build character portion
    character_prompt = character_state.build_detailed_character_prompt

    # Build background portion with consistency
    background_prompt = character_state.build_detailed_background_prompt

    # Build system prompt explaining the structure
    system_prompt = build_system_prompt_for_structured_generation

    # Combine into unified scene prompt with explicit structure
    unified_prompt = <<~PROMPT
      #{system_prompt}

      CHARACTER DETAILS:
      #{character_prompt}

      SCENE BACKGROUND:
      #{background_prompt}

      TECHNICAL_SPECIFICATIONS:
      art_style: anime art style, high quality, detailed illustration, visual novel style
      composition: cinematic composition, professional lighting
      quality: masterpiece, best quality, ultra detailed
    PROMPT

    unified_prompt.strip
  end

  private

  def build_system_prompt_for_structured_generation
    <<~SYSTEM
      Generate a visual novel scene image based on the following structured prompt.
      Each section provides explicit details that should be incorporated into the final image:
      
      - CHARACTER DETAILS: Contains structured character information including physical features, clothing, expression, and pose
      - SCENE BACKGROUND: Contains structured environment information including setting, lighting, and atmosphere
      - TECHNICAL_SPECIFICATIONS: Contains art style and quality requirements
      
      Please interpret each labeled section (e.g., "physical_features:", "hair_details:", "environment:") as specific visual elements to include in the generated image.
    SYSTEM
  end

  private

  def attach_base64_image(character_state, attachment_name, base64_data, filename)
    Rails.logger.info "Starting image attachment process for #{attachment_name}"

    begin
      # Decode base64 data
      image_data = Base64.decode64(base64_data)
      Rails.logger.info "Decoded base64 data, size: #{image_data.bytesize} bytes"

      # Use StringIO instead of Tempfile to avoid file closure issues
      string_io = StringIO.new(image_data)
      string_io.set_encoding(Encoding::BINARY)
      Rails.logger.info "Created StringIO object for attachment"

      # Attach to the model using StringIO
      character_state.public_send(attachment_name).attach(
        io: string_io,
        filename: filename,
        content_type: "image/png",
      )

      Rails.logger.info "Successfully attached #{attachment_name} to character_state #{character_state.id}"
    rescue => e
      Rails.logger.error "Failed to attach image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end
