class GenerateImageJob < ApplicationJob
  # Standard negative prompt for quality and safety
  DEFAULT_NEGATIVE_PROMPT = [
    "worst quality", "low quality", "blurry", "out of focus",
    "deformed", "disfigured", "bad anatomy", "bad proportions",
    "extra limbs", "mutated hands", "fused fingers",
    "duplicate", "clone", "multiple people",
    "child", "minor", "young", "teen", "teenager"
  ].join(", ").freeze

  def perform(user, prompt, opts = {})
    client = user.api_client
    return unless client

    venice_client = VeniceClient::ImageApi.new(client)

    style = user.image_style

    # Use the user's image model method which handles fallback logic
    model = user.image_model

    # Extract negative prompt from opts or use default
    negative_prompt = opts.delete(:negative_prompt) || DEFAULT_NEGATIVE_PROMPT

    options = {
      model: model,
      prompt: prompt.first(user.prompt_limit),
      negative_prompt: negative_prompt,
      safe_mode: user.safe_mode?,
      format: "png",
      **opts
    }

    # Respect explicit style in opts if provided; otherwise fall back to user's image_style
    Rails.logger.debug "Generating image pre: #{options}"
    if opts.key?(:style_preset)
      options[:style_preset] = opts[:style_preset].presence
    elsif style.present?
      options[:style_preset] = style
    end
    options.compact!

    Rails.logger.info "Generating image with seed: #{options[:seed]}, prompt length: #{options[:prompt].length}"
    Rails.logger.debug "Full image options: #{options}"

    response = venice_client.generate_image({
      generate_image_request: options
    })

    response.images.first
  end
end
