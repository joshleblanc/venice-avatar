class ImageEditService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  def edit_scene_image(new_message_content, message_timestamp = nil)
    Rails.logger.info "Starting scene image edit for conversation: #{@conversation.id}"

    # Get the current scene image
    current_image = get_current_scene_image
    unless current_image
      Rails.logger.info "No current scene image found, falling back to full generation"
      return generate_new_scene_image
    end

    # Generate edit prompt based on the message content
    edit_prompt = generate_edit_prompt(new_message_content, message_timestamp)

    # Convert current image to base64
    base64_image = image_to_base64(current_image)

    # Edit the image using Venice API
    file = EditImageJob.perform_now(@conversation.user, base64_image, edit_prompt)

    if file
      file.open
      @conversation.scene_image.attach(
        io: file,
        filename: "scene.png",
        content_type: "image/png",
      )
      @conversation.scene_image
    else
      debugger
      Rails.logger.error "Failed to edit scene image, falling back to full generation"
      generate_new_scene_image
    end
  rescue => e
    debugger
    Rails.logger.error "Image edit service failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    # Fallback to full generation
    generate_new_scene_image
  end

  private

  def get_current_scene_image
    return nil unless @conversation.scene_image.attached?
    @conversation.scene_image
  end

  def generate_edit_prompt(new_message_content, message_timestamp = nil)
    Rails.logger.info "Generating edit prompt for message: #{new_message_content}"

    # Get current scene context
    current_scene_prompt = get_current_scene_context

    # Build time context if timestamp provided
    time_context = build_time_context(message_timestamp)

    prompt = build_edit_prompt_request(current_scene_prompt, new_message_content, time_context)

    begin
      edit_prompt = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "user",
          content: prompt,
        },
      ])

      Rails.logger.info "Generated edit prompt: #{edit_prompt}"
      edit_prompt
    rescue => e
      Rails.logger.error "Failed to generate edit prompt: #{e.message}"
      # Fallback to simple edit prompt
      "Update the scene based on: #{new_message_content}"
    end
  end

  def build_edit_prompt_request(current_scene_prompt, new_message_content, time_context)
    character_name = @character.name || "Character"

    <<~PROMPT
      You are an image editing prompt generator. Your task is to create a concise edit instruction for modifying an existing scene image.

      Current Scene Context: #{current_scene_prompt}
      
      New Message from #{character_name}: "#{new_message_content}"
      #{time_context}

      Generate a brief, specific edit instruction that describes ONLY what should change in the image based on the new message. Focus on:

      1. Character changes (clothing, expression, pose, appearance)
      2. Environmental changes (lighting, objects, background elements)
      3. Atmospheric changes (mood, time of day)

      Guidelines:
      - Be specific and concise (under 200 characters)
      - Only describe what needs to CHANGE, not the entire scene
      - Use direct, actionable language
      - Focus on visual elements that can be edited
      - If time has passed significantly, consider clothing/location changes
      - Do not include character names
      - Use present tense

      Examples:
      - "Change expression to smiling, add warm lighting"
      - "Remove jacket, change to casual t-shirt"
      - "Dim lighting to evening ambiance, add soft shadows"
      - "Change pose to sitting, add relaxed posture"

      Return only the edit instruction:
    PROMPT
  end

  def build_time_context(message_timestamp)
    return "" unless message_timestamp

    # Get the last message timestamp for comparison
    last_message = @conversation.messages.where.not(id: @conversation.messages.last&.id).last
    return "" unless last_message&.created_at

    time_gap = message_timestamp - last_message.created_at
    hours_passed = (time_gap / 1.hour).round

    if hours_passed >= 8
      "\n\nTime Context: #{hours_passed} hours have passed since the last interaction. Consider significant changes like different clothes, location, or time of day."
    elsif hours_passed >= 2
      "\n\nTime Context: #{hours_passed} hours have passed. Consider moderate changes in appearance or setting."
    elsif hours_passed >= 1
      "\n\nTime Context: About #{hours_passed} hour has passed. Consider minor changes in pose or lighting."
    else
      ""
    end
  end

  def get_current_scene_context
    # Try to get from conversation metadata first
    if @conversation.metadata.present? && @conversation.metadata["current_scene_prompt"]
      return @conversation.metadata["current_scene_prompt"]
    end

    # Fallback to basic character description
    "#{@character.name} in a scene"
  end

  def image_to_base64(image_attachment)
    Rails.logger.info "Converting image attachment to base64"

    # Download the image data
    image_data = image_attachment.download

    # Convert to base64
    Base64.encode64(image_data).gsub(/\n/, "")
  end

  def attach_base64_image_to_conversation(base64_data, filename)
    Rails.logger.info "Attaching edited image to conversation"

    begin
      # Decode base64 data
      image_data = Base64.decode64(base64_data)
      Rails.logger.info "Decoded base64 data, size: #{image_data.bytesize} bytes"

      # Use StringIO for attachment
      string_io = StringIO.new(image_data)
      string_io.set_encoding(Encoding::BINARY)

      # Attach to the conversation, replacing the existing scene image
      @conversation.scene_image.attach(
        io: string_io,
        filename: filename,
        content_type: "image/png",
      )

      Rails.logger.info "Successfully attached edited scene_image to conversation #{@conversation.id}"
    rescue => e
      Rails.logger.error "Failed to attach edited image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end

  def generate_new_scene_image
    Rails.logger.info "Falling back to full scene image generation"
    image_service = ImageGenerationService.new(@conversation)
    image_service.generate_scene_image
  end
end
