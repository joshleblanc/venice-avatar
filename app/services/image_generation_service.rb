class ImageGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @venice_client = VeniceClient::ImageApi.new
  end

  def generate_character_image(character_state)
    return character_state.character_image.url if character_state.character_image.attached?

    prompt = build_character_prompt(character_state)

    begin
      response = @venice_client.generate_image({
        body: {
          prompt: prompt,
          style_preset: "Anime",
          model: "hidream",
          width: 768,  # 3:4 ratio for character portraits
          height: 1024,
          safe_mode: false,
        },
      })

      # Handle base64 response
      Rails.logger.info "Character image response: #{response.inspect}"
      base64_data = response.images.first
      if base64_data
        attach_base64_image(character_state, :character_image, base64_data, "character.png")
        character_state.character_image.url
      end
    rescue => e
      Rails.logger.error "Failed to generate character image: #{e.message}"
      nil
    end
  end

  def generate_background_image(character_state)
    return character_state.background_image.url if character_state.background_image.attached?

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
        },
      })

      # Handle base64 response
      Rails.logger.info "Background image response: #{response.inspect}"
      base64_data = response.images.first
      if base64_data
        attach_base64_image(character_state, :background_image, base64_data, "background.png")
        character_state.background_image.url
      end
    rescue => e
      Rails.logger.error "Failed to generate background image: #{e.message}"
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
    base_prompt = "Full body portrait of #{@character.name}, "

    # Add character description
    if character_state.appearance_description.present?
      base_prompt += "#{character_state.appearance_description}, "
    end

    # Add expression
    if character_state.expression.present?
      base_prompt += "with #{character_state.expression} expression, "
    end

    # Add clothing details
    if character_state.clothing_details.present? && character_state.clothing_details["latest_change"]
      base_prompt += "wearing #{character_state.clothing_details["latest_change"]}, "
    end

    # Add injury details if present
    if character_state.injury_details.present? && character_state.injury_details["latest_injury"]
      base_prompt += "showing #{character_state.injury_details["latest_injury"]}, "
    end

    # Visual novel style specifications
    base_prompt += "visual novel character art style, anime style, high quality, detailed, standing pose, clean background"

    base_prompt
  end

  def build_background_prompt(character_state)
    base_prompt = character_state.background_prompt || "A cozy indoor setting"

    # Visual novel style specifications
    "#{base_prompt}, visual novel background, anime art style, detailed environment, no characters, static scene, high quality"
  end

  private

  def attach_base64_image(character_state, attachment_name, base64_data, filename)
    # Decode base64 data
    image_data = Base64.decode64(base64_data)

    # Create a temporary file
    temp_file = Tempfile.new([filename.split(".").first, ".png"])
    temp_file.binmode
    temp_file.write(image_data)
    temp_file.rewind

    # Attach to the model
    character_state.public_send(attachment_name).attach(
      io: temp_file,
      filename: filename,
      content_type: "image/png",
    )

    temp_file.close
    temp_file.unlink
  end
end
