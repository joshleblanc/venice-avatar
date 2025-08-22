class GenerateCharacterAvatarJob < ApplicationJob
  limits_concurrency to: 1, key: ->(character, *_rest) { character }
  queue_as :default

  def perform(character, user)
    # Skip if avatar already exists
    return if character.avatar.attached?

    # Skip if no appearance description available
    return if character.appearance.blank?

    Rails.logger.info "Generating avatar headshot for character: #{character.name}"

    # Build headshot prompt using stored appearance
    prompt = build_headshot_prompt_from_appearance(character)

    begin
      base64_data = GenerateImageJob.perform_now(user, prompt, {
        width: 512,
        height: 512,
      })

      if base64_data
        Rails.logger.info "Received headshot base64 image data, length: #{base64_data.length}"
        attach_base64_avatar(character, base64_data, "#{character.slug}_avatar.png")
        Rails.logger.info "Successfully generated and attached avatar for character: #{character.name}"

        # Broadcast update to refresh UI
        character.broadcast_refresh
      else
        Rails.logger.error "No base64 headshot image data received from Venice API"
      end
    rescue => e
      Rails.logger.error "Failed to generate character avatar: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end

  private

  def build_headshot_prompt_from_appearance(character)
    # Use stored appearance to create headshot prompt
    Rails.logger.info "Building headshot prompt from stored appearance"

    appearance = character.appearance

    # Create professional headshot prompt from appearance description
    <<~PROMPT
      Professional headshot portrait based on this description: #{appearance}
      
      Anime style illustration, head and shoulders view, clean professional lighting, neutral background.
      High quality, detailed facial features, friendly expression, direct gaze.
      Sharp focus on face, soft background blur, 1 subject
    PROMPT
  end

  def attach_base64_avatar(character, base64_data, filename)
    Rails.logger.info "Starting avatar attachment process for character: #{character.name}"

    begin
      # Decode base64 data
      image_data = Base64.decode64(base64_data)
      Rails.logger.info "Decoded base64 data, size: #{image_data.bytesize} bytes"

      # Use StringIO for attachment
      string_io = StringIO.new(image_data)
      string_io.set_encoding(Encoding::BINARY)
      Rails.logger.info "Created StringIO object for avatar attachment"

      # Attach to the character
      character.avatar.attach(
        io: string_io,
        filename: filename,
        content_type: "image/png",
      )

      Rails.logger.info "Successfully attached avatar to character #{character.id}"
    rescue => e
      Rails.logger.error "Failed to attach avatar: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end
