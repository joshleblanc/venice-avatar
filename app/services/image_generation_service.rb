class ImageGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @venice_client = VeniceClient::ImageApi.new
  end

  def generate_scene_image
    # Always generate new scene images - don't return early if one exists
    # This allows background generation while showing previous scenes

    prompt = build_unified_scene_prompt

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
          prompt: prompt.first(2048),
          style_preset: "Anime",
          negative_prompt: "border, frame, text, watermark, signature, blurry, low quality",
          model: models[4],
          width: 640,  # 16:10 ratio for visual novel scenes
          height: 1024,
          safe_mode: false,
          format: "png",
          cfg_scale: 15,
          seed: 123456,
        },
      })

      # Handle base64 response
      base64_data = response.images.first
      if base64_data
        Rails.logger.info "Received unified scene base64 image data, length: #{base64_data.length}"
        attach_base64_image_to_conversation(base64_data, "scene.png")

        # Return the attached scene image
        @conversation.scene_image
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

  def generate_all_images
    scene_image = generate_scene_image
    {
      scene_image: scene_image,
    }
  end

  private

  def build_unified_scene_prompt
    # Use AI-based prompt generation service
    prompt_service = AiPromptGenerationService.new(@conversation)
    prompt = prompt_service.get_current_scene_prompt

    Rails.logger.info "AI-generated scene prompt length: #{prompt.length}"

    prompt
  end

  private

  def attach_base64_image_to_conversation(base64_data, filename)
    Rails.logger.info "Starting image attachment process for conversation scene_image"

    begin
      # Decode base64 data
      image_data = Base64.decode64(base64_data)
      Rails.logger.info "Decoded base64 data, size: #{image_data.bytesize} bytes"

      # Use StringIO instead of Tempfile to avoid file closure issues
      string_io = StringIO.new(image_data)
      string_io.set_encoding(Encoding::BINARY)
      Rails.logger.info "Created StringIO object for attachment"

      # Attach to the conversation using StringIO
      @conversation.scene_image.attach(
        io: string_io,
        filename: filename,
        content_type: "image/png",
      )

      Rails.logger.info "Successfully attached scene_image to conversation #{@conversation.id}"
    rescue => e
      Rails.logger.error "Failed to attach image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end
