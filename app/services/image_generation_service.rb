class ImageGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @venice_client = VeniceClient::ImageApi.new
  end

  def generate_character_image(character_state)
    return character_state.character_image if character_state.character_image.attached?

    prompt = build_character_prompt(character_state)

    begin
      response = @venice_client.generate_image({
        body: {
          prompt: prompt,
          style_preset: "Anime",
          negative_prompt: "border, frame, background, decoration",
          model: "hidream",
          width: 768,  # 3:4 ratio for character portraits
          height: 1024,
          safe_mode: false,
          format: "png",
        },
      })

      # Handle base64 response
      base64_data = response.images.first
      if base64_data
        Rails.logger.info "Received base64 image data, length: #{base64_data.length}"

        # Use BackgroundRemovalService to process and attach the image with transparent background
        success = BackgroundRemovalService.process_and_attach(
          character_state,
          :character_image,
          base64_data,
          "character.png"
        )

        # Save the character state to ensure attachment is persisted
        if success && character_state.save
          Rails.logger.info "Character state saved successfully with processed image attachment"
          character_state.character_image
        elsif !success
          Rails.logger.warn "Background removal failed, falling back to original image"
          attach_base64_image(character_state, :character_image, base64_data, "character.png")
          character_state.save ? character_state.character_image : nil
        else
          Rails.logger.error "Failed to save character state: #{character_state.errors.full_messages}"
          nil
        end
      else
        Rails.logger.error "No base64 image data received from Venice API"
        nil
      end
    rescue => e
      Rails.logger.error "Failed to generate character image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end

  def generate_background_image(character_state)
    return character_state.background_image if character_state.background_image.attached?

    prompt = build_background_prompt(character_state)

    begin
      response = @venice_client.generate_image({
        body: {
          prompt: prompt,
          style_preset: "Anime",
          model: "hidream",
          width: 1024,  # 16:9 ratio for background landscapes
          height: 576,
          safe_mode: false,
          format: "png",
        },
      })

      # Handle base64 response
      base64_data = response.images.first
      if base64_data
        Rails.logger.info "Received background base64 image data, length: #{base64_data.length}"
        attach_base64_image(character_state, :background_image, base64_data, "background.png")

        # Save the character state to ensure attachment is persisted
        if character_state.save
          Rails.logger.info "Character state saved successfully with background image attachment"
          character_state.background_image
        else
          Rails.logger.error "Failed to save character state: #{character_state.errors.full_messages}"
          nil
        end
      else
        Rails.logger.error "No base64 background image data received from Venice API"
        nil
      end
    rescue => e
      Rails.logger.error "Failed to generate background image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end

  def generate_all_images(character_state)
    {
      character_image: generate_character_image(character_state),
      background_image: generate_background_image(character_state),
    }
  end

  private

  def build_character_prompt(character_state)
    # Initialize detailed character description if not already done
    character_state.initialize_base_character_description(@character)

    # Use the new detailed character prompt system
    detailed_prompt = character_state.build_detailed_character_prompt

    # Add visual novel specific requirements - request white background for consistent removal
    "#{detailed_prompt}, solid white background, clean white backdrop, isolated character on white, simple white background"
  end

  def build_background_prompt(character_state)
    base_prompt = character_state.background_prompt || "A cozy indoor setting"

    # Visual novel style specifications
    "#{base_prompt}, visual novel background, anime art style, detailed environment, no characters, static scene, high quality"
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

      Rails.logger.info "Successfully attached #{attachment_name} to character_state"
    rescue => e
      Rails.logger.error "Failed to attach image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end
