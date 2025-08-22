class GenerateImageJob < ApplicationJob
  def perform(user, prompt, opts = {})
    return unless user.venice_key.present?

    venice_client = VeniceClient::ImageApi.new(user.api_client)

    style = user.image_style 

    options = {
      model: user.image_model,
      prompt: prompt.first(user.prompt_limit),
      safe_mode: user.safe_mode,
      format: "png",
      seed: 123871273,
      **opts,
    }
    # Respect explicit style in opts if provided; otherwise fall back to user's image_style
    Rails.logger.debug "Generating image pre: #{options}"
    if opts.key?(:style_preset)
      options[:style_preset] = opts[:style_preset].presence
    else
      options[:style_preset] = style if style.present?
    end
    options.compact!
    Rails.logger.debug "Generating image: #{options}"
    
    response = venice_client.generate_image({
      generate_image_request: options,
    })

    response.images.first
  end
end
