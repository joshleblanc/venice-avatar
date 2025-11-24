class ImageGenerationService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @prompt_builder = ConsistentPromptBuilderService.new(conversation)
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
    Rails.logger.info "Generating full scene image with consistency service"

    # Determine if we have a real scene prompt yet
    has_real_prompt = @conversation.metadata.present? && @conversation.metadata["current_scene_prompt"].present?

    # Use the new consistent prompt builder for better character consistency
    prompt_data = @prompt_builder.build(trigger: "full_scene")
    prompt = prompt_data[:prompt]
    negative_prompt = prompt_data[:negative_prompt]
    seed = prompt_data[:seed]

    begin
      mode = has_real_prompt ? "full" : "fast-first"
      width, height = has_real_prompt ? [1024, 640] : [320, 512]
      Rails.logger.info "Generating unified scene image (mode=#{mode}, #{width}x#{height}) with prompt length=#{prompt.length}, seed=#{seed}"

      # Conversation-specific style override
      style_override = @conversation.metadata&.dig("image_style_override")

      Rails.logger.debug "Style override: #{style_override.inspect}"

      opts = {
        width: width,
        height: height,
        seed: seed,
        negative_prompt: negative_prompt
      }

      if style_override == "__none__"
        # Explicitly disable style preset
        opts[:style_preset] = ""
      elsif style_override.present?
        opts[:style_preset] = style_override
      end

      base64_data = GenerateImageJob.perform_now(@conversation.user, prompt, opts)
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
      scene_image: scene_image
    }
  end

  def generate_scene_image_with_prompt(prompt, message_timestamp = nil)
    return nil if prompt.blank?

    Rails.logger.info "Generating scene image from provided prompt with length=#{prompt.length}"

    # Get negative prompt and seed from consistency service
    prompt_data = @prompt_builder.build(trigger: "provided_prompt")
    negative_prompt = prompt_data[:negative_prompt]
    seed = prompt_data[:seed]

    style_override = @conversation.metadata&.dig("image_style_override")
    opts = {
      width: 1024,
      height: 640,
      seed: seed,
      negative_prompt: negative_prompt
    }

    if style_override == "__none__"
      opts[:style_preset] = ""
    elsif style_override.present?
      opts[:style_preset] = style_override
    end

    begin
      base64_data = GenerateImageJob.perform_now(@conversation.user, prompt, opts)
      if base64_data
        Rails.logger.info "Received base64 image data from provided prompt, length: #{base64_data.length}"
        attach_base64_image_to_conversation(base64_data, "scene.png")
        @conversation.scene_image
      else
        Rails.logger.error "No base64 data received when generating image from provided prompt"
        nil
      end
    rescue => e
      Rails.logger.error "Failed to generate scene image from provided prompt: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end

  private

  # Content validation to ensure no child references in image generation prompts
  #
  # @param [String] prompt The image generation prompt to validate
  # @return [String] The validated and filtered prompt
  def validate_content_for_image_generation(prompt)
    return prompt if prompt.blank?

    # List of child-related terms to filter out
    child_terms = [
      "child", "children", "kid", "kids", "baby", "babies", "toddler", "toddlers",
      "infant", "infants", "minor", "minors", "boy", "boys", "girl", "girls",
      "son", "daughter", "nephew", "niece", "student", "students", "pupil", "pupils",
      "schoolchild", "schoolchildren", "youngster", "youngsters", "youth", "youths",
      "juvenile", "juveniles", "adolescent", "adolescents", "teen", "teens",
      "teenager", "teenagers", "preteen", "preteens", "tween", "tweens",
      "school", "playground", "nursery", "daycare", "kindergarten"
    ]

    filtered_prompt = prompt.dup

    # Remove words and phrases containing child-related terms
    child_terms.each do |term|
      # Remove the term and surrounding context
      filtered_prompt.gsub!(/\b\w*#{Regexp.escape(term)}\w*\b/i, "")
      # Clean up extra spaces
      filtered_prompt.gsub!(/\s+/, " ")
    end

    # Remove sentences that might still contain problematic content
    sentences = filtered_prompt.split(/[.!?]+/)
    safe_sentences = sentences.select do |sentence|
      # Keep sentences that don't contain age-related numbers that might indicate minors
      !sentence.match?(/\b(?:1[0-7]|[1-9])\s*(?:year|yr)s?\s*old\b/i) &&
        !sentence.match?(/\b(?:young|little|small|tiny)\s+(?:person|people|human|figure)\b/i)
    end

    # If all sentences were filtered out, return a safe default
    if safe_sentences.empty? || filtered_prompt.strip.length < 20
      character_name = @character&.name || "character"
      return "Adult #{character_name} in a comfortable indoor setting with warm lighting, detailed character design, mature atmosphere"
    end

    # Ensure the prompt explicitly mentions adult content
    validated_prompt = safe_sentences.join(". ").strip
    unless validated_prompt.match?(/\b(?:adult|mature|grown)\b/i)
      validated_prompt = "Adult " + validated_prompt
    end

    validated_prompt + "."
  end

  def should_use_image_editing?
    # Use image editing for minor changes to preserve character consistency
    # Requirements:
    # 1. A scene image already exists
    # 2. Character is not away (we can't edit background-only scenes)
    # 3. Conversation has messages (not the initial scene)
    # 4. The change type is suitable for editing
    return false unless @conversation.scene_image.attached?
    return false if @conversation.character_away?
    return false unless @conversation.messages.exists?

    # Use the edit service to determine if the change is suitable
    edit_service = ImageEditService.new(@conversation)
    change_type = edit_service.detect_change_type

    Rails.logger.info "Detected change type: #{change_type}"

    # Only use editing for minor changes
    ImageEditService::EDIT_SUITABLE_CHANGES.include?(change_type)
  end

  def build_unified_scene_prompt
    # Use AI-based prompt generation service
    prompt_service = AiPromptGenerationService.new(@conversation)
    prompt = prompt_service.get_current_scene_prompt

    # Apply content validation to ensure no child references
    validated_prompt = validate_content_for_image_generation(prompt)

    Rails.logger.info "AI-generated scene prompt length: #{validated_prompt.length}"

    validated_prompt
  end

  def build_background_only_prompt
    # Generate background-only scene when character is away
    prompt_service = AiPromptGenerationService.new(@conversation)
    current_prompt = prompt_service.get_current_scene_prompt

    # Request Venice to generate just the background description
    begin
      background_description = ChatCompletionJob.perform_now(@conversation.user, [
        {
          role: "system",
          content: "You are a visual scene description expert. Extract and describe only the background/environment elements from the given scene description. Remove all references to people, characters, clothing, expressions, or human features. Focus only on the location, architecture, furniture, lighting, atmosphere, and environmental details. Return a clean background description suitable for image generation."
        },
        {
          role: "user",
          content: "Extract the background-only description from this scene: #{current_prompt}"
        }
      ], {
        temperature: 0.3
      })

      # Add explicit background-only instructions for image generation
      enhanced_prompt = "Empty room scene, no people, no characters. #{background_description}. Detailed interior background, ambient lighting, peaceful atmosphere"

      # Apply content validation to background prompt
      validated_prompt = validate_content_for_image_generation(enhanced_prompt)

      Rails.logger.info "Generated background-only prompt: #{validated_prompt}"
      @conversation.update(metadata: (@conversation.metadata || {}).merge(background_only_prompt: validated_prompt))

      validated_prompt
    rescue => e
      Rails.logger.error "Failed to generate background description via Venice: #{e.message}"

      # Fallback to a simple default background
      fallback_prompt = "Empty room scene, no people, no characters. Cozy indoor setting with warm lighting, comfortable furniture, peaceful atmosphere"

      # Apply content validation to fallback prompt
      validated_fallback = validate_content_for_image_generation(fallback_prompt)

      Rails.logger.info "Using fallback background prompt: #{validated_fallback}"
      @conversation.update(metadata: (@conversation.metadata || {}).merge(background_only_prompt: validated_fallback))

      validated_fallback
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
        content_type: "image/png"
      )

      Rails.logger.info "Successfully attached scene_image to conversation #{@conversation.id}"
    rescue => e
      Rails.logger.error "Failed to attach image: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end
end
