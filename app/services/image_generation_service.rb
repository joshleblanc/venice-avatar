class ImageGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  def generate_scene_image(new_message_content = nil, message_timestamp = nil)
    # Check if we should use image editing instead of full generation
    if should_use_image_editing? && new_message_content
      Rails.logger.info "Using image editing for scene evolution"
      edit_service = ImageEditService.new(@conversation)
      return edit_service.edit_scene_image(new_message_content, message_timestamp)
    end

    # Fall back to full image generation
    generate_full_scene_image
  end

  def generate_full_scene_image
    Rails.logger.info "Generating full scene image from scratch"

    # Determine if we have a real scene prompt yet
    has_real_prompt = @conversation.metadata.present? && @conversation.metadata["current_scene_prompt"].present?

    # Check if character is away and generate appropriate prompt
    prompt = if @conversation.character_away?
        build_background_only_prompt
      else
        build_unified_scene_prompt
      end

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
      mode = has_real_prompt ? "full" : "fast-first"
      width, height = has_real_prompt ? [640, 1024] : [320, 512]
      Rails.logger.info "Generating unified scene image (mode=#{mode}, #{width}x#{height}) with prompt length=#{prompt.length}"

      base64_data = GenerateImageJob.perform_now(@conversation.user, prompt, {
        width: width,
        height: height,
      })
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

  def should_use_image_editing?
    # Use image editing if:
    # 1. A scene image already exists
    # 2. Character is not away (we can't edit background-only scenes effectively)
    # 3. Conversation has messages (not the initial scene)
    # @conversation.scene_image.attached? &&
    #   !@conversation.character_away? &&
    #   @conversation.messages.exists?
    false # doesn't really work yet
  end

  def build_unified_scene_prompt
    # Use AI-based prompt generation service
    prompt_service = AiPromptGenerationService.new(@conversation)
    prompt = prompt_service.get_current_scene_prompt

    Rails.logger.info "AI-generated scene prompt length: #{prompt.length}"

    prompt
  end

  def build_background_only_prompt
    # Generate background-only scene when character is away
    prompt_service = AiPromptGenerationService.new(@conversation)
    current_prompt = prompt_service.get_current_scene_prompt

    # Request Venice to generate just the background description
    begin
      background_tags = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "system",
          content: "You are a visual scene tags generator. Extract ONLY background/environment tags from a scene tag list. Return a concise, lowercase, comma-separated tag list (no quotes, no sentences). Remove all references to people or human features.",
        },
        {
          role: "user",
          content: "Extract background-only tags from this scene tags list: #{current_prompt}",
        },
      ], {
        temperature: 0.2,
      })

      combined = [
        "empty room",
        "no people",
        "no characters",
        background_tags,
        "detailed interior background",
        "ambient lighting",
        "peaceful atmosphere",
      ].compact.join(", ")

      enhanced_prompt = PromptUtils.normalize_tag_list(combined, max_len: @conversation.user.prompt_limit, always_include: [])

      Rails.logger.info "Generated background-only prompt: #{enhanced_prompt}"

      enhanced_prompt
    rescue => e
      Rails.logger.error "Failed to generate background description via Venice: #{e.message}"

      # Fallback to a simple default background in tag style
      fallback_prompt = PromptUtils.normalize_tag_list(
        "empty room, no people, no characters, cozy indoor setting, warm lighting, comfortable furniture, peaceful atmosphere",
        max_len: @conversation.user.prompt_limit,
        always_include: [],
      )

      Rails.logger.info "Using fallback background prompt: #{fallback_prompt}"

      fallback_prompt
    end
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
